// SPDX-License-Identifier: GPL-2.0-or-later
//
// US-16x08 Panel: an unofficial control panel for the TASCAM US-16x08.
// Not affiliated with TASCAM / TEAC Corporation, the Linux kernel or ALSA
// maintainers, or the GNU Project.
//
// Derivative work. The USB protocol knowledge used here comes from the Linux
// kernel driver sound/usb/mixer_us16x08.c, Copyright (c) 2016 by Detlef Urban,
// GPL-2.0-or-later.
//
// This program is free software; you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation; either version 2 of the License, or (at your option) any later
// version. It is distributed WITHOUT ANY WARRANTY. See the file COPYING.

import Foundation
import CoreAudio
import AudioToolbox

/// Plays sine tones on chosen output channels of one audio device (AUHAL).
/// Used by the automated test to push known audio into the unit.
/// Per-channel values are plain floats written from the control thread and read by the
/// render thread; a torn read here only means one buffer of slightly stale level.
public final class ToneGenerator {
    public enum ToneError: Error, CustomStringConvertible {
        case audio(String, OSStatus)
        public var description: String {
            switch self {
            case .audio(let what, let status): return "\(what) failed (OSStatus \(status))"
            }
        }
    }

    fileprivate static let maxChannels = 64
    private var unit: AudioUnit?
    fileprivate let amps = UnsafeMutablePointer<Float>.allocate(capacity: ToneGenerator.maxChannels)
    fileprivate let freqs = UnsafeMutablePointer<Float>.allocate(capacity: ToneGenerator.maxChannels)
    fileprivate let phases = UnsafeMutablePointer<Double>.allocate(capacity: ToneGenerator.maxChannels)
    public private(set) var channelCount = 0
    public private(set) var sampleRate = 44100.0

    public init() {
        amps.initialize(repeating: 0, count: ToneGenerator.maxChannels)
        freqs.initialize(repeating: 1000, count: ToneGenerator.maxChannels)
        phases.initialize(repeating: 0, count: ToneGenerator.maxChannels)
    }

    deinit {
        stop()
        amps.deallocate()
        freqs.deallocate()
        phases.deallocate()
    }

    private func check(_ status: OSStatus, _ what: String) throws {
        if status != noErr { throw ToneError.audio(what, status) }
    }

    public func start(device: AudioDeviceID) throws {
        stop()
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0)
        guard let comp = AudioComponentFindNext(nil, &desc) else { throw ToneError.audio("find output component", -1) }
        var created: AudioUnit?
        try check(AudioComponentInstanceNew(comp, &created), "create output unit")
        guard let u = created else { throw ToneError.audio("create output unit", -1) }
        unit = u

        var dev = device
        try check(AudioUnitSetProperty(u, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                       &dev, UInt32(MemoryLayout<AudioDeviceID>.size)), "select device")

        // The hardware side of the output element tells us the device's channel count and rate.
        var hw = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioUnitGetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0,
                                       &hw, &size), "read device format")
        channelCount = min(Int(hw.mChannelsPerFrame), ToneGenerator.maxChannels)
        sampleRate = hw.mSampleRate

        var fmt = AudioStreamBasicDescription(
            mSampleRate: hw.mSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: UInt32(channelCount),
            mBitsPerChannel: 32,
            mReserved: 0)
        try check(AudioUnitSetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0,
                                       &fmt, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)), "set stream format")

        var callback = AURenderCallbackStruct(inputProc: toneRenderProc,
                                              inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        try check(AudioUnitSetProperty(u, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0,
                                       &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)), "set render callback")
        try check(AudioUnitInitialize(u), "initialise output unit")
        try check(AudioOutputUnitStart(u), "start output unit")
    }

    public func stop() {
        guard let u = unit else { return }
        AudioOutputUnitStop(u)
        AudioUnitUninitialize(u)
        AudioComponentInstanceDispose(u)
        unit = nil
    }

    /// `channel` is 0-based (0 = Computer 1 / USB out 1).
    public func setTone(channel: Int, frequency: Double, levelDBFS: Double) {
        guard channel >= 0 && channel < ToneGenerator.maxChannels else { return }
        freqs[channel] = Float(frequency)
        amps[channel] = Float(pow(10.0, levelDBFS / 20.0))
    }

    public func silenceAll() {
        for i in 0..<ToneGenerator.maxChannels { amps[i] = 0 }
    }

    fileprivate func render(frames: Int, ioData: UnsafeMutablePointer<AudioBufferList>?) {
        guard let ioData = ioData else { return }
        let list = UnsafeMutableAudioBufferListPointer(ioData)
        let twoPi = 2.0 * Double.pi
        for ch in 0..<list.count {
            guard let raw = list[ch].mData else { continue }
            let out = raw.assumingMemoryBound(to: Float.self)
            let c = min(ch, ToneGenerator.maxChannels - 1)
            let amp = amps[c]
            if amp == 0 {
                for i in 0..<frames { out[i] = 0 }
                continue
            }
            let inc = twoPi * Double(freqs[c]) / sampleRate
            var ph = phases[c]
            for i in 0..<frames {
                out[i] = amp * Float(sin(ph))
                ph += inc
                if ph >= twoPi { ph -= twoPi }
            }
            phases[c] = ph
        }
    }
}

private let toneRenderProc: AURenderCallback = { refCon, _, _, _, frames, ioData in
    Unmanaged<ToneGenerator>.fromOpaque(refCon).takeUnretainedValue().render(frames: Int(frames), ioData: ioData)
    return noErr
}
