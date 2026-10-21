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

/// Owns the transport and serialises all USB traffic on one queue.
/// - Control changes are coalesced by key (dragging a fader sends the latest
///   value, not hundreds of intermediates).
/// - Meter polling runs on the same queue so transfers never interleave.
public final class DeviceLink {
    private let transport: US16x08Transport
    private let queue = DispatchQueue(label: "us16x08.link")
    private var pending: [OutboundMessage] = []
    private var flushScheduled = false

    /// Called on the link's queue; hop to the main thread in UI code.
    public var onLog: ((String) -> Void)?
    public var onError: ((String) -> Void)?

    public init(transport: US16x08Transport) { self.transport = transport }

    // MARK: Control
    public func send(key: String, _ bytes: [UInt8]) {
        queue.async {
            if let i = self.pending.firstIndex(where: { $0.key == key }) {
                self.pending[i] = OutboundMessage(key: key, bytes: bytes)
            } else {
                self.pending.append(OutboundMessage(key: key, bytes: bytes))
            }
            if !self.flushScheduled {
                self.flushScheduled = true
                self.queue.asyncAfter(deadline: .now() + 0.012) { self.flush() }
            }
        }
    }

    /// Sends messages strictly in order with a gap between them (used for
    /// "send all" and for EQ switch changes, which the Linux driver spaces 15 ms apart).
    public func sendSequence(_ messages: [OutboundMessage], gap: TimeInterval = 0.015) {
        queue.async {
            self.flush()
            for m in messages {
                self.transmit(m.bytes)
                Thread.sleep(forTimeInterval: gap)
            }
        }
    }

    private func flush() {
        flushScheduled = false
        let batch = pending
        pending.removeAll()
        for m in batch {
            transmit(m.bytes)
            Thread.sleep(forTimeInterval: 0.003)
        }
    }

    private func transmit(_ bytes: [UInt8]) {
        do {
            try transport.send(bytes)
            onLog?("OUT \(hexString(bytes))")
        } catch {
            onError?("\(error)")
        }
    }

    // MARK: Metering
    public enum MeterStatus: Equatable {
        case running
        /// The unit stopped answering. Polling carries on slowly and resumes by itself.
        case retrying(String)
    }

    private var meterTimer: DispatchSourceTimer?
    private var meterStep = 0
    private var compCursor = 0
    private var meterErrors = 0
    private var meterRetrying = false
    private var meterInterval = 1.0 / 50.0
    private var levels = MeterLevels()
    /// Called on the link queue when the poller enters or leaves its slow "unit not responding" mode.
    public var onMeterStatus: ((MeterStatus) -> Void)?
    /// Which channels currently have their compressor on (read on the link queue).
    public var compEnabledChannels: () -> [Bool] = { [] }

    /// Each tick performs one step of the unit's four-step meter cycle, so a full refresh of every
    /// meter takes four ticks. 50 Hz therefore gives about 12 refreshes per second. The handler runs
    /// on the link queue; keep it cheap and never publish to SwiftUI from here.
    public func startMeters(hz: Double = 50, handler: @escaping (MeterLevels) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.stopMetersLocked()
            self.meterErrors = 0
            self.meterRetrying = false
            self.meterInterval = 1.0 / hz
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: self.meterInterval, leeway: .milliseconds(3))
            timer.setEventHandler { [weak self] in
                guard let self = self else { return }
                if let l = self.pollMeterStep() { handler(l) }
            }
            self.meterTimer = timer
            timer.resume()
        }
    }

    public func stopMeters() { queue.async { self.stopMetersLocked() } }

    private func stopMetersLocked() {
        meterTimer?.cancel()
        meterTimer = nil
    }

    /// One step of the four-step meter cycle used by the Linux driver:
    /// 0: send init1 + read, 1: read, 2: read, 3: send init2(comp channel) + read.
    private func pollMeterStep() -> MeterLevels? {
        do {
            switch meterStep {
            case 0: try transport.send(Messages.meterInit1)
            case 3: try transport.send(Messages.meterInit2(compChannel: nextCompChannel()))
            default: break
            }
            let frame = try transport.readMeterFrame(length: US16x08.Request.meterFrameLength)
            meterStep = (meterStep + 1) % 4
            MeterParser.update(&levels, frame: frame)
            if meterRetrying {
                meterRetrying = false
                meterTimer?.schedule(deadline: .now() + meterInterval, repeating: meterInterval, leeway: .milliseconds(3))
                onMeterStatus?(.running)
            }
            meterErrors = 0
            return levels
        } catch {
            // Brief hiccups are ignored. After ~0.4 s of failures drop to one poll per second and
            // say so once; resume full speed automatically when the unit answers again.
            meterErrors += 1
            if meterErrors == 20 {
                meterRetrying = true
                onError?("meter poll: \(error). Retrying once a second.")
                onMeterStatus?(.retrying("\(error)"))
                meterTimer?.schedule(deadline: .now() + 1.0, repeating: 1.0, leeway: .milliseconds(50))
            }
            return nil
        }
    }

    private func nextCompChannel() -> Int {
        let on = compEnabledChannels()
        for _ in 0..<US16x08.channelCount {
            compCursor = (compCursor + 1) % US16x08.channelCount
            if compCursor < on.count && on[compCursor] { return compCursor + 1 }
        }
        return 1
    }

    /// Mirrors the original panel: poll until the unit reports ready (tag 0xA1), send the
    /// version query, then read frames until both version and build replies have been seen.
    /// Read-only. Blocks for up to ~0.8 s, so call it off the main thread.
    public func readFirmware() throws -> FirmwareInfo {
        try queue.sync { () throws -> FirmwareInfo in
            var info = FirmwareInfo()
            for _ in 0..<100 {
                let frame = try transport.readMeterFrame(length: US16x08.Request.meterFrameLength)
                info.lastFrame = frame
                if TLV.parse(frame).contains(where: { $0.tag == 0xA1 && !$0.value.isEmpty }) {
                    info.readyTagSeen = true
                    break
                }
                Thread.sleep(forTimeInterval: 0.005)
            }
            try transport.send(Messages.versionQuery)
            for _ in 0..<50 {
                let frame = try transport.readMeterFrame(length: US16x08.Request.meterFrameLength)
                info.lastFrame = frame
                Firmware.extract(from: frame, into: &info)
                if info.versionRaw != nil && info.buildRaw != nil { break }
                Thread.sleep(forTimeInterval: 0.005)
            }
            return info
        }
    }

    /// One-shot synchronous read used by the CLI `probe` command.
    public func probeMeterFrame() throws -> [UInt8] {
        try queue.sync { () throws -> [UInt8] in
            try transport.send(Messages.meterInit1)
            return try transport.readMeterFrame(length: US16x08.Request.meterFrameLength)
        }
    }
}
