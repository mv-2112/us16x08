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
import CUSB
import CoreAudio

/// What the Mac can tell us about the unit without any vendor protocol:
/// USB descriptors (IORegistry) and the Core Audio device.
public struct DeviceStatus: Equatable {
    public var present = false
    public var productName: String?
    public var vendorName: String?
    public var serial: String?
    public var usbSpeed: String?
    /// bcdDevice formatted as "2.10". Whether this equals the firmware version is unconfirmed.
    public var deviceRelease: String?
    public var sampleRate: Double?
    public var audioDeviceName: String?
    /// Bits per sample of the device's current physical stream format (16 or 24 on this unit).
    public var bitDepth: Int?
    /// Nominal sample rates macOS offers for the device, ascending.
    public var supportedRates: [Double] = []
    public init() {}

    /// "44.1 kHz · 24-bit"
    public var formatText: String? {
        guard let r = sampleRateText else { return nil }
        return bitDepth.map { "\(r) · \($0)-bit" } ?? r
    }

    /// "44.1, 48, 88.2, 96 kHz"
    public var supportedRatesText: String? {
        guard !supportedRates.isEmpty else { return nil }
        let parts = supportedRates.map { r -> String in
            let k = r / 1000
            return k == k.rounded() ? String(format: "%.0f", k) : String(format: "%.1f", k)
        }
        return parts.joined(separator: ", ") + " kHz"
    }

    /// The unit is specified for 44.1, 48, 88.2 and 96 kHz at 16 or 24 bit.
    public static let specifiedRates: [Double] = [44100, 48000, 88200, 96000]

    public var sampleRateText: String? {
        guard let r = sampleRate else { return nil }
        let khz = r / 1000.0
        return khz == khz.rounded() ? String(format: "%.0f kHz", khz) : String(format: "%.1f kHz", khz)
    }
}

public enum DeviceInfo {
    private static let speeds = [
        "Low speed (1.5 Mbit/s)", "Full speed (12 Mbit/s)", "High speed (480 Mbit/s)",
        "SuperSpeed (5 Gbit/s)", "SuperSpeed+ (10 Gbit/s)",
    ]

    /// Parses the "key=value" lines produced by `cusb_info_text`.
    public static func apply(infoText: String, to s: inout DeviceStatus) {
        for line in infoText.split(separator: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<eq])
            let value = String(line[line.index(after: eq)...])
            switch key {
            case "USB Product Name": s.productName = value
            case "USB Vendor Name": s.vendorName = value
            case "USB Serial Number": s.serial = value
            case "bcdDevice":
                if let v = Int(value) { s.deviceRelease = String(format: "%x.%02x", (v >> 8) & 0xff, v & 0xff) }
            case "Device Speed":
                if let v = Int(value) { s.usbSpeed = v >= 0 && v < speeds.count ? speeds[v] : "code \(v)" }
            default: break
            }
        }
    }

    public static func query() -> DeviceStatus {
        var s = DeviceStatus()
        let size = 2048
        var buf = [CChar](repeating: 0, count: size)
        let n = cusb_info_text(US16x08.vendorID, US16x08.productID, &buf, size)
        if n >= 0 {
            s.present = true
            apply(infoText: String(cString: buf), to: &s)
        }
        if let (name, rate) = findAudioDevice() {
            s.audioDeviceName = name
            s.sampleRate = rate
        }
        if let id = audioDeviceID() {
            s.supportedRates = availableRates(id)
            s.bitDepth = bitsPerChannel(id)
        }
        return s
    }

    private static func availableRates(_ id: AudioDeviceID) -> [Double] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: Int(size) / MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &ranges) == noErr else { return [] }
        // Each entry is a (min, max) pair; discrete rates have min == max.
        let rates = ranges.flatMap { r -> [Double] in r.mMinimum == r.mMaximum ? [r.mMinimum] : [r.mMinimum, r.mMaximum] }
        return Array(Set(rates)).sorted()
    }

    /// Bit depth of the first output stream (falls back to the first input stream).
    private static func bitsPerChannel(_ id: AudioDeviceID) -> Int? {
        for scope in [kAudioObjectPropertyScopeOutput, kAudioObjectPropertyScopeInput] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams, mScope: scope, mElement: kAudioObjectPropertyElementMain)
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size >= 4 else { continue }
            var streams = [AudioStreamID](repeating: 0, count: Int(size) / MemoryLayout<AudioStreamID>.size)
            guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &streams) == noErr, let first = streams.first else { continue }
            var fmtAddress = AudioObjectPropertyAddress(
                mSelector: kAudioStreamPropertyPhysicalFormat,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var asbd = AudioStreamBasicDescription()
            var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            if AudioObjectGetPropertyData(first, &fmtAddress, 0, nil, &asbdSize, &asbd) == noErr, asbd.mBitsPerChannel > 0 {
                return Int(asbd.mBitsPerChannel)
            }
        }
        return nil
    }

    /// Core Audio id of the first device whose name contains "US-16x08".
    public static func audioDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dataSize: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &dataSize) == noErr else { return nil }
        var ids = [AudioDeviceID](repeating: 0, count: Int(dataSize) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &dataSize, &ids) == noErr else { return nil }
        for id in ids {
            if let name = audioName(id), name.lowercased().contains("us-16x08") { return id }
        }
        return nil
    }

    private static func findAudioDevice() -> (String, Double)? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dataSize: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &dataSize) == noErr else { return nil }
        var ids = [AudioDeviceID](repeating: 0, count: Int(dataSize) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &dataSize, &ids) == noErr else { return nil }
        for id in ids {
            guard let name = audioName(id), name.lowercased().contains("us-16x08") else { continue }
            var rateAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var rate: Float64 = 0
            var rateSize = UInt32(MemoryLayout<Float64>.size)
            if AudioObjectGetPropertyData(id, &rateAddress, 0, nil, &rateSize, &rate) == noErr {
                return (name, rate)
            }
            return (name, 0)
        }
        return nil
    }

    private static func audioName(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr,
              let cf = name?.takeRetainedValue() else { return nil }
        return cf as String
    }
}
