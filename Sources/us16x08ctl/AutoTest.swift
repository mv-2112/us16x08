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
import US16x08Core

/// Automated audio test. The Mac plays 1 kHz tones into the unit over USB and the unit's own
/// level meters (read over the vendor protocol) report what happened, so every check is a
/// measured pass/fail. No microphone permission is needed: the Mac only plays audio.
///
/// Stage 1 (no cables): USB out 1/2 -> Computer out to Stereo Bus -> master meters.
/// Stage 2 (one cable, LINE OUT 8 -> LINE IN 16): the tone returns as input channel 16.

struct Averages {
    var master = [Double](repeating: 0, count: 2)
    var input = [Double](repeating: 0, count: US16x08.channelCount)
    var comp = [Double](repeating: 0, count: US16x08.channelCount)
    var samples = 0
}

final class MeterSampler {
    private let lock = NSLock()
    private var recorded: [MeterLevels] = []
    private var recording = false

    func feed(_ l: MeterLevels) {
        lock.lock()
        if recording { recorded.append(l) }
        lock.unlock()
    }

    /// Waits for things to settle, then averages the meter stream over `seconds`.
    func measure(seconds: Double, settle: Double = 0.5) -> Averages {
        Thread.sleep(forTimeInterval: settle)
        lock.lock()
        recorded.removeAll()
        recording = true
        lock.unlock()
        Thread.sleep(forTimeInterval: seconds)
        lock.lock()
        recording = false
        let s = recorded
        lock.unlock()
        var a = Averages()
        guard !s.isEmpty else { return a }
        let n = Double(s.count)
        for l in s {
            for i in 0..<2 { a.master[i] += Double(l.master[i]) / n }
            for i in 0..<US16x08.channelCount {
                a.input[i] += Double(l.input[i]) / n
                a.comp[i] += Double(l.compReduction[i]) / n
            }
        }
        a.samples = s.count
        return a
    }
}

func runAutoTest(level: Double, assumeYes: Bool) {
    var report: [String] = []
    var passes = 0, fails = 0, infos = 0
    func say(_ s: String) { print(s); report.append(s) }
    func check(_ name: String, _ ok: Bool, _ detail: String) {
        if ok { passes += 1 } else { fails += 1 }
        say("  \(ok ? "PASS" : "FAIL")  \(name) — \(detail)")
    }
    func note(_ name: String, _ detail: String) {
        infos += 1
        say("  INFO  \(name) — \(detail)")
    }
    func n0(_ v: Double) -> String { String(format: "%.0f", v) }
    func n1(_ v: Double) -> String { String(format: "%.1f", v) }
    func finish() {
        say("\nResult: \(passes) passed, \(fails) failed, \(infos) info.")
        let path = "us16x08-autotest-report.txt"
        try? report.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        print("Report saved to ./\(path) — paste it back to me.")
    }

    say("US-16x08 automated audio test  \(Date())")
    say("Tone: 1 kHz at \(Int(level)) dBFS (stage 2: \(Int(min(level + 12, -6))) dBFS)")
    print("""

    This plays a test tone from the Mac into the unit. It WILL be audible on outputs 1/2 and the
    headphones during the test. Turn monitors and headphone volume down first.
    Stage 2 needs one cable: LINE OUT 8 -> LINE IN 16 (any level setting). It is skipped if no
    loopback is detected.
    """)
    if !assumeYes {
        print("Press Return to start…", terminator: "")
        _ = readLine()
    }

    // ---- set up audio + control ----
    guard let deviceID = DeviceInfo.audioDeviceID() else {
        say("FAIL: no Core Audio device named \"US-16x08\" found. Is it plugged in and powered?")
        finish()
        return
    }
    let tone = ToneGenerator()
    do { try tone.start(device: deviceID) } catch {
        say("FAIL: could not start audio output: \(error)")
        finish()
        return
    }
    defer { tone.stop() }
    say("Audio: \(tone.channelCount) output channels @ \(Int(tone.sampleRate)) Hz")
    guard tone.channelCount >= 8 else {
        say("FAIL: expected at least 8 output channels (Computer 1-8).")
        finish()
        return
    }
    let transport: USBTransport
    do { transport = try USBTransport() } catch {
        say("FAIL: \(error)")
        finish()
        return
    }
    let link = DeviceLink(transport: transport)
    link.onError = { say("  ERROR: \($0)") }
    var compOn = [Bool](repeating: false, count: US16x08.channelCount)
    link.compEnabledChannels = { compOn }
    let sampler = MeterSampler()
    link.startMeters(hz: 60) { sampler.feed($0) }
    defer { link.stopMeters() }

    func send(_ bytes: [UInt8]) {
        link.send(key: UUID().uuidString, bytes)
        Thread.sleep(forTimeInterval: 0.06)
    }
    func setEQ(on: Bool, gain: Int) {
        link.sendSequence((0..<4).map {
            let d = EQBandSettings.defaults[$0]
            return OutboundMessage(key: "eq\($0)", bytes: Messages.eqBand(
                channel: 15, band: $0, EQBandSettings(gain: gain, frequency: d.frequency, width: d.width), enabled: on))
        })
        Thread.sleep(forTimeInterval: 0.3)
    }
    func playing(_ channels: [Int], _ dB: Double) {
        tone.silenceAll()
        for c in channels { tone.setTone(channel: c, frequency: 1000, levelDBFS: dB) }
    }
    func avg() -> Averages { sampler.measure(seconds: 0.6) }
    func mid(_ a: Averages) -> Double { (a.master[0] + a.master[1]) / 2 }

    func baseline() {
        send(Messages.masterFader(db: 0)); send(Messages.masterMute(on: false))
        send(Messages.bypass(on: false)); send(Messages.bussOut(on: true))
        send(Messages.route(output: 0, sourceIndex: 0)); send(Messages.route(output: 1, sourceIndex: 1))
        send(Messages.route(output: 7, sourceIndex: 9))
        send(Messages.fader(channel: 15, db: 0)); send(Messages.pan(channel: 15, position: 0))
        send(Messages.mute(channel: 15, on: false)); send(Messages.phase(channel: 15, on: false))
        compOn[15] = false
        send(Messages.compressor(channel: 15, CompressorSettings()))
        setEQ(on: false, gain: 12)
    }
    defer { baseline() }   // leave the unit in a known, normal state

    baseline()
    playing([], level)
    let quiet = avg()
    let floor = (quiet.master[0] + quiet.master[1]) / 2 + 1
    say("Silence: master L \(n0(quiet.master[0])) R \(n0(quiet.master[1])), input 16 \(n0(quiet.input[15])) (\(quiet.samples) meter samples)")
    if quiet.samples == 0 { say("FAIL: no meter data received."); finish(); return }
    // Which open inputs are feeding the master while the Mac is silent? (e.g. a guitar at full gain)
    let idle = quiet.input.enumerated().filter { $0.element > 3 }.map { "ch\($0.offset + 1)=\(n0($0.element))" }
    say("Inputs above idle noise: \(idle.isEmpty ? "none" : idle.joined(separator: ", "))")
    if !idle.isEmpty {
        say("  (these feed the master. If the master floor is high, unplug them or turn their gain down for cleaner results.)")
    }

    func strong(_ v: Double) -> Bool { v > floor * 6 + 30 }
    func weak(_ v: Double, than base: Double, _ f: Double) -> Bool { v <= base * f + floor * 2 }

    // ================= STAGE 1 =================
    say("\nSTAGE 1 — Computer out -> Stereo Bus -> Master (no cables)")
    playing([0], level)
    var a = avg()
    check("USB out 1 (odd) -> Stereo L only",
          strong(a.master[0]) && weak(a.master[1], than: a.master[0], 0.15),
          "L \(n0(a.master[0])), R \(n0(a.master[1]))")
    playing([1], level)
    a = avg()
    check("USB out 2 (even) -> Stereo R only",
          strong(a.master[1]) && weak(a.master[0], than: a.master[1], 0.15),
          "L \(n0(a.master[0])), R \(n0(a.master[1]))")

    playing([0, 1], level)
    a = avg()
    let B = mid(a)
    let reaches = strong(a.master[0]) && strong(a.master[1])
    check("Tone reaches both master meters", reaches, "L \(n0(a.master[0])), R \(n0(a.master[1])), floor \(n0(floor))")
    if reaches {
        send(Messages.masterMute(on: true)); a = avg()
        check("Master mute silences the master", weak(a.master[0], than: B, 0.15) && weak(a.master[1], than: B, 0.15),
              "L \(n0(a.master[0])), R \(n0(a.master[1])) vs \(n0(B))")
        send(Messages.masterMute(on: false))

        send(Messages.masterFader(db: -30)); a = avg()
        check("Master fader -30 dB lowers level", weak(a.master[0], than: B, 0.5) && weak(a.master[1], than: B, 0.5),
              "L \(n0(a.master[0])), R \(n0(a.master[1])) vs \(n0(B))")
        send(Messages.masterFader(db: -127)); a = avg()
        check("Master fader -inf silences", weak(a.master[0], than: B, 0.1) && weak(a.master[1], than: B, 0.1),
              "L \(n0(a.master[0])), R \(n0(a.master[1])) vs \(n0(B))")
        send(Messages.masterFader(db: 0))

        send(Messages.bussOut(on: false)); a = avg()
        check("Computer out to Stereo BUS OFF removes the tone", weak(a.master[0], than: B, 0.15) && weak(a.master[1], than: B, 0.15),
              "L \(n0(a.master[0])), R \(n0(a.master[1])) vs \(n0(B))")
        send(Messages.bussOut(on: true))

        send(Messages.bypass(on: true)); a = avg()
        note("Mixer True Bypass ON (no verdict)", "master L \(n0(a.master[0])), R \(n0(a.master[1])) vs \(n0(B)) with bypass off")
        send(Messages.bypass(on: false))
    } else {
        say("  (skipping the rest of stage 1: no usable signal on the master meters)")
    }

    // ================= STAGE 2 =================
    say("\nSTAGE 2 — Input channel 16 via loopback cable (LINE OUT 8 -> LINE IN 16)")
    let level2 = min(level + 12, -6)
    send(Messages.bussOut(on: false))          // keep the computer tone out of the stereo bus
    playing([7], level2)
    a = avg()
    let inLevel = a.input[15]
    if !(inLevel > quiet.input[15] * 6 + 50) {
        say("  SKIP  no loopback detected on input 16 (meter \(n0(inLevel)) vs silence \(n0(quiet.input[15]))). Connect LINE OUT 8 -> LINE IN 16 to run this stage.")
    } else {
        check("Loopback detected on input 16", true, "meter \(n0(inLevel)) vs silence \(n0(quiet.input[15]))")
        let M = mid(a)
        let reaches2 = strong(a.master[0]) && strong(a.master[1])
        check("Channel 16 reaches the master", reaches2, "L \(n0(a.master[0])), R \(n0(a.master[1])), floor \(n0(floor))")
        if reaches2 {
            send(Messages.mute(channel: 15, on: true)); a = avg()
            check("Channel mute", weak(a.master[0], than: M, 0.15) && weak(a.master[1], than: M, 0.15),
                  "L \(n0(a.master[0])), R \(n0(a.master[1])) vs \(n0(M))")
            send(Messages.mute(channel: 15, on: false))

            send(Messages.fader(channel: 15, db: -20)); a = avg()
            check("Channel fader -20 dB lowers level", weak(a.master[0], than: M, 0.5) && weak(a.master[1], than: M, 0.5),
                  "L \(n0(a.master[0])), R \(n0(a.master[1])) vs \(n0(M))")
            let inDrop = 20 * log10(max(a.input[15], 1) / max(inLevel, 1))
            note("Input 16 meter with the fader at -20 dB",
                 "\(n1(inDrop)) dB vs fader at 0 dB -> \(abs(inDrop) < 1.5 ? "meter is pre-fader" : "meter is post-fader")")
            send(Messages.fader(channel: 15, db: -127)); a = avg()
            check("Channel fader -inf silences", weak(a.master[0], than: M, 0.1) && weak(a.master[1], than: M, 0.1),
                  "L \(n0(a.master[0])), R \(n0(a.master[1])) vs \(n0(M))")
            send(Messages.fader(channel: 15, db: 0))

            send(Messages.pan(channel: 15, position: -127)); a = avg()
            check("Pan hard left", strong(a.master[0]) && weak(a.master[1], than: a.master[0], 0.25),
                  "L \(n0(a.master[0])), R \(n0(a.master[1]))")
            send(Messages.pan(channel: 15, position: 127)); a = avg()
            check("Pan hard right", strong(a.master[1]) && weak(a.master[0], than: a.master[1], 0.25),
                  "L \(n0(a.master[0])), R \(n0(a.master[1]))")
            send(Messages.pan(channel: 15, position: 0)); a = avg()
            check("Pan centre is balanced", abs(a.master[0] - a.master[1]) <= 0.35 * max(a.master[0], a.master[1]),
                  "L \(n0(a.master[0])), R \(n0(a.master[1]))")

            setEQ(on: true, gain: 24); a = avg()
            check("EQ, all bands +12 dB, raises level", mid(a) >= M * 1.3, "\(n0(mid(a))) vs \(n0(M))")
            setEQ(on: true, gain: 0); a = avg()
            check("EQ, all bands -12 dB, lowers level", mid(a) <= M * 0.77, "\(n0(mid(a))) vs \(n0(M))")
            setEQ(on: true, gain: 24)
            send(Messages.bypass(on: true)); a = avg()
            note("Mixer True Bypass ON with EQ +12 dB",
                 "master \(n0(mid(a))) vs \(n0(M)) flat and 32767 (clipped) with EQ and no bypass -> \(abs(mid(a) - M) <= 0.25 * M ? "bypass skips the EQ" : "EQ still applies")")
            send(Messages.bypass(on: false))
            setEQ(on: false, gain: 12); a = avg()
            check("EQ off restores level", abs(mid(a) - M) <= 0.25 * M, "\(n0(mid(a))) vs \(n0(M))")

            var comp = CompressorSettings()
            comp.enabled = true; comp.thresholdDB = -32; comp.ratioIndex = 14; comp.attackMS = 2; comp.releaseSteps = 1
            compOn[15] = true
            send(Messages.compressor(channel: 15, comp)); a = avg()
            check("Compressor lowers level", mid(a) <= M * 0.8, "\(n0(mid(a))) vs \(n0(M))")
            let dropDB = 20 * log10(M / max(mid(a), 1))
            let grDB = MeterScale.reductionDB(Int(a.comp[15]))
            check("Compressor gain-reduction meter matches the level drop", abs(grDB - dropDB) <= 3,
                  "GR meter \(n1(grDB)) dB, master dropped \(n1(dropDB)) dB")
            compOn[15] = false
            send(Messages.compressor(channel: 15, CompressorSettings()))
        }

        send(Messages.route(output: 7, sourceIndex: 8)); a = avg()      // out 8 <- Computer 7 (silent)
        check("Route: LINE OUT 8 <- Computer 7 breaks the loopback", weak(a.input[15], than: inLevel, 0.15),
              "input 16 \(n0(a.input[15])) vs \(n0(inLevel))")
        send(Messages.route(output: 7, sourceIndex: 9))
        note("Phase invert", "not measurable with a single channel; skipped")
    }

    say("\nRestoring a normal baseline…")
    playing([], level)
    finish()
}
