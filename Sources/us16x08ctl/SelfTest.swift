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

/// Guided hardware test. Each step changes ONE thing, asks what you observed,
/// then restores it. Results go to ./us16x08-selftest-report.txt so they can be
/// pasted back for analysis.
struct TestStep {
    let title: String
    let expect: String
    /// "yn" = pass/fail question, "note" = free-text observation.
    let kind: String
    let apply: () -> Void
    let revert: () -> Void
}

func runSelfTest(dry: Bool) {
    var report: [String] = []
    func say(_ s: String) { print(s); report.append(s) }

    say("US-16x08 self-test  \(Date())")
    say("Highband EQ freq offset: \(Messages.highBandFrequencyOffset)")

    // --- connect
    let transport: US16x08Transport
    if dry { transport = DryRunTransport() }
    else {
        do { transport = try USBTransport() }
        catch {
            say("FAIL connect: \(error)")
            say("Other devices seen:\n" + USBTransport.listDevices())
            finish(report); return
        }
    }
    say("PASS connect")
    let link = DeviceLink(transport: transport)
    link.onError = { say("  ERROR: \($0)") }

    // --- automatic: protocol handshake
    do {
        let frame = try link.probeMeterFrame()
        let ok = (0..<6).contains { s in
            let b = s * 10 + 4
            return frame[b] == 0x61 && frame[b + 1] == 0x02 && frame[b + 3] == 0x62
        }
        say(ok ? "PASS meter handshake (documented frame layout recognised)"
               : "FAIL meter handshake. Frame: \(hexString(frame))")
    } catch { say("FAIL meter handshake: \(error)") }

    func now(_ bytes: [UInt8]) {
        link.send(key: UUID().uuidString, bytes)
        Thread.sleep(forTimeInterval: 0.08)
    }
    func eqEnable(_ on: Bool) {
        link.sendSequence((0..<4).map {
            OutboundMessage(key: "eq\($0)", bytes: Messages.eqBand(channel: 0, band: $0, EQBandSettings.defaults[$0], enabled: on))
        })
        Thread.sleep(forTimeInterval: 0.2)
    }

    // --- baseline
    say("\nBASELINE: feed a steady signal (mic, music, tone) into INPUT 1 and listen on")
    say("outputs 1/2 or the headphones. Wait — setting Input 1 to 0 dB, centre, unmuted;")
    say("master 0 dB, unmuted, Mixer True Bypass off, Computer out to Stereo BUS on, outs 1/2 = Master L/R. Press Return to apply.")
    _ = readLine()
    now(Messages.fader(channel: 0, db: 0)); now(Messages.pan(channel: 0, position: 0))
    now(Messages.mute(channel: 0, on: false)); now(Messages.masterFader(db: 0))
    now(Messages.masterMute(on: false)); now(Messages.bypass(on: false)); now(Messages.bussOut(on: true))
    now(Messages.route(output: 0, sourceIndex: 0)); now(Messages.route(output: 1, sourceIndex: 1))
    eqEnable(false)
    now(Messages.compressor(channel: 0, CompressorSettings()))

    var low = EQBandSettings.defaults[0]; low.gain = 24
    var high = EQBandSettings.defaults[3]; high.gain = 24
    var hard = CompressorSettings(); hard.enabled = true; hard.thresholdDB = -32; hard.ratioIndex = 14; hard.gainDB = 0

    let steps: [TestStep] = [
        TestStep(title: "Input 1 mute ON", expect: "Input 1 goes SILENT in the monitor mix.", kind: "yn",
                 apply: { now(Messages.mute(channel: 0, on: true)) },
                 revert: { now(Messages.mute(channel: 0, on: false)) }),
        TestStep(title: "Input 1 fader to -inf", expect: "Input 1 goes SILENT.", kind: "yn",
                 apply: { now(Messages.fader(channel: 0, db: -127)) },
                 revert: { now(Messages.fader(channel: 0, db: 0)) }),
        TestStep(title: "Input 1 fader to -20 dB", expect: "Input 1 is clearly QUIETER (not silent).", kind: "yn",
                 apply: { now(Messages.fader(channel: 0, db: -20)) },
                 revert: { now(Messages.fader(channel: 0, db: 0)) }),
        TestStep(title: "Input 1 pan hard LEFT", expect: "Signal ONLY in the LEFT ear / output 1.", kind: "yn",
                 apply: { now(Messages.pan(channel: 0, position: -127)) },
                 revert: { now(Messages.pan(channel: 0, position: 0)) }),
        TestStep(title: "Input 1 pan hard RIGHT", expect: "Signal ONLY in the RIGHT ear / output 2.", kind: "yn",
                 apply: { now(Messages.pan(channel: 0, position: 127)) },
                 revert: { now(Messages.pan(channel: 0, position: 0)) }),
        TestStep(title: "Master mute ON", expect: "Mixer output goes SILENT on outputs 1/2.", kind: "yn",
                 apply: { now(Messages.masterMute(on: true)) },
                 revert: { now(Messages.masterMute(on: false)) }),
        TestStep(title: "Master fader to -30 dB", expect: "Mixer output is much QUIETER.", kind: "yn",
                 apply: { now(Messages.masterFader(db: -30)) },
                 revert: { now(Messages.masterFader(db: 0)) }),
        TestStep(title: "Route: swap outs (out1<-Master R, out2<-Master L) with Input 1 panned LEFT",
                 expect: "Signal now appears on the RIGHT side (swapped).", kind: "yn",
                 apply: {
                     now(Messages.pan(channel: 0, position: -127))
                     now(Messages.route(output: 0, sourceIndex: 1)); now(Messages.route(output: 1, sourceIndex: 0))
                 },
                 revert: {
                     now(Messages.route(output: 0, sourceIndex: 0)); now(Messages.route(output: 1, sourceIndex: 1))
                     now(Messages.pan(channel: 0, position: 0))
                 }),
        TestStep(title: "EQ ON, LOW band +12 dB", expect: "Noticeably MORE BASS on Input 1.", kind: "yn",
                 apply: { eqEnable(true); now(Messages.eqBand(channel: 0, band: 0, low, enabled: true)) },
                 revert: { eqEnable(false) }),
        TestStep(title: "EQ ON, HIGH band +12 dB, freq step default", expect: "Noticeably MORE TREBLE (note roughly where).", kind: "yn",
                 apply: { eqEnable(true); now(Messages.eqBand(channel: 0, band: 3, high, enabled: true)) },
                 revert: { eqEnable(false) }),
        TestStep(title: "EQ HIGH band freq sweep: step 0 then step 31, +12 dB",
                 expect: "Describe: does the boost move from ~2 kHz-ish (step 0) up to ~air/18 kHz (step 31)? Or does it sound the same / odd? (This checks the +0x20 assumption; re-run with --kernel-high-freq to compare.)",
                 kind: "note",
                 apply: {
                     eqEnable(true)
                     var a = high; a.frequency = 0; now(Messages.eqBand(channel: 0, band: 3, a, enabled: true))
                     print("   (step 0 now — listen, press Return)"); _ = readLine()
                     var b = high; b.frequency = 31; now(Messages.eqBand(channel: 0, band: 3, b, enabled: true))
                     print("   (step 31 now — listen)")
                 },
                 revert: { eqEnable(false) }),
        TestStep(title: "Compressor ON, threshold -32 dB, max ratio",
                 expect: "Loud signal is clearly SQUASHED / level drops. (Use a signal with some dynamics.)", kind: "yn",
                 apply: { now(Messages.compressor(channel: 0, hard)) },
                 revert: { now(Messages.compressor(channel: 0, CompressorSettings())) }),
        TestStep(title: "Mixer True Bypass ON (v2.10)",
                 expect: "Per the release notes: input and output are matched binary, the mixer's processing (faders, EQ, comp) is skipped. Describe what you hear (or 'nothing').", kind: "note",
                 apply: { now(Messages.bypass(on: true)) },
                 revert: { now(Messages.bypass(on: false)) }),
        TestStep(title: "Computer out to Stereo BUS OFF",
                 expect: "With audio playing from the computer: it should drop out of the mixer's stereo bus (Master L/R). Describe what you hear (or 'nothing').", kind: "note",
                 apply: { now(Messages.bussOut(on: false)) },
                 revert: { now(Messages.bussOut(on: true)) }),
    ]

    for (i, step) in steps.enumerated() {
        say("\n[\(i + 1)/\(steps.count)] \(step.title)")
        step.apply()
        print("   EXPECT: \(step.expect)")
        if step.kind == "yn" {
            print("   Did that happen?  [y]es / [n]o / [s]kip: ", terminator: "")
            let a = (readLine() ?? "s").lowercased()
            say("   -> " + (a.hasPrefix("y") ? "PASS" : a.hasPrefix("n") ? "FAIL" : "SKIP"))
        } else {
            print("   Observation (one line): ", terminator: "")
            say("   -> NOTE: " + (readLine() ?? ""))
        }
        step.revert()
    }
    link.stopMeters()
    say("\nDone. Baseline restored where possible.")
    finish(report)
}

private func finish(_ report: [String]) {
    let path = "us16x08-selftest-report.txt"
    try? report.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    print("\nReport saved to ./\(path) — paste it back to me.")
}
