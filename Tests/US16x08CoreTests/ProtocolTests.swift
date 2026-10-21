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

import XCTest
@testable import US16x08Core

/// Golden vectors come from `tools/ref_vectors.py`, a literal port of the
/// Linux driver's message construction. If these pass, our builders produce
/// the same bytes as the driver for the same logical inputs.
final class ProtocolTests: XCTestCase {

    private func h(_ b: [UInt8]) -> String { hexString(b) }

    func testFaders() {
        XCTAssertEqual(h(Messages.fader(channel: 0, db: 0)),   "61 02 04 62 02 01 81 02 00 00 00")
        XCTAssertEqual(h(Messages.fader(channel: 15, db: -127)), "61 02 04 62 02 10 81 02 81 00 00")
        XCTAssertEqual(h(Messages.fader(channel: 2, db: 6)),   "61 02 04 62 02 03 81 02 06 00 00")
        XCTAssertEqual(h(Messages.fader(channel: 4, db: -10)), "61 02 04 62 02 05 81 02 f6 00 00")
    }

    func testFaderClamps() {
        XCTAssertEqual(Messages.fader(channel: 0, db: 99), Messages.fader(channel: 0, db: 6))
        XCTAssertEqual(Messages.fader(channel: 0, db: -999), Messages.fader(channel: 0, db: -127))
    }

    func testPan() {
        XCTAssertEqual(h(Messages.pan(channel: 1, position: 0)),    "61 02 04 62 02 02 82 02 00 00 00")
        XCTAssertEqual(h(Messages.pan(channel: 1, position: 127)),  "61 02 04 62 02 02 82 02 7f 00 00")
        XCTAssertEqual(h(Messages.pan(channel: 1, position: -127)), "61 02 04 62 02 02 82 02 81 00 00")
    }

    func testSwitches() {
        XCTAssertEqual(h(Messages.mute(channel: 3, on: true)),  "61 02 04 62 02 04 83 02 01 00 00")
        XCTAssertEqual(h(Messages.phase(channel: 0, on: true)), "61 02 04 62 02 01 85 02 01 00 00")
    }

    func testMasterAndBus() {
        XCTAssertEqual(h(Messages.masterFader(db: -10)), "61 02 02 62 02 01 81 02 f6 00 00")
        XCTAssertEqual(h(Messages.masterMute(on: true)), "61 02 02 62 02 01 83 02 01 00 00")
        XCTAssertEqual(h(Messages.bypass(on: true)),     "45 02 01 00 00")
        XCTAssertEqual(h(Messages.bussOut(on: false)),   "44 02 00 00 00")
    }

    func testRouting() {
        XCTAssertEqual(h(Messages.route(output: 0, sourceIndex: 1)),
                       "61 02 02 62 02 02 41 01 61 02 01 62 02 01 42 01 43 01 00 00")
        XCTAssertEqual(h(Messages.route(output: 7, sourceIndex: 9)),
                       "61 02 03 62 02 08 41 01 61 02 01 62 02 08 42 01 43 01 00 00")
        XCTAssertEqual(h(Messages.route(output: 2, sourceIndex: 4)),
                       "61 02 03 62 02 03 41 01 61 02 01 62 02 03 42 01 43 01 00 00")
    }

    func testCompressor() {
        XCTAssertEqual(h(Messages.compressor(channel: 0, CompressorSettings())),
                       "61 02 04 62 02 01 91 02 00 92 02 0a 93 02 02 94 02 01 95 02 00 96 02 01 97 02 00 00 00")
        var c = CompressorSettings()
        c.enabled = true; c.thresholdDB = -20; c.ratioIndex = 14
        c.attackMS = 100; c.releaseSteps = 50; c.gainDB = 10
        XCTAssertEqual(h(Messages.compressor(channel: 5, c)),
                       "61 02 04 62 02 06 91 02 ec 92 02 ff 93 02 64 94 02 32 95 02 0a 96 02 01 97 02 01 00 00")
    }

    func testEQ() {
        XCTAssertEqual(h(Messages.eqBand(channel: 0, band: 0, EQBandSettings.defaults[0], enabled: false)),
                       "61 02 04 62 02 01 51 02 01 52 02 0c 53 02 05 54 02 ff 55 02 00 00 00")
        let s = EQBandSettings(gain: 20, frequency: 0x1b, width: 4)
        XCTAssertEqual(h(Messages.eqBand(channel: 3, band: 2, s, enabled: true)),
                       "61 02 04 62 02 04 51 02 03 52 02 14 53 02 1b 54 02 04 55 02 01 00 00")
    }

    func testHighBandFrequencyOffset() {
        let saved = Messages.highBandFrequencyOffset
        defer { Messages.highBandFrequencyOffset = saved }
        // Linux-driver-literal behaviour (offset 0):
        Messages.highBandFrequencyOffset = 0
        XCTAssertEqual(h(Messages.eqBand(channel: 0, band: 3, EQBandSettings.defaults[3], enabled: true)),
                       "61 02 04 62 02 01 51 02 04 52 02 0c 53 02 0f 54 02 ff 55 02 01 00 00")
        // Our assumed hardware behaviour: default 0x0f + 0x20 = 0x2f.
        Messages.highBandFrequencyOffset = 0x20
        XCTAssertEqual(Messages.eqBand(channel: 0, band: 3, EQBandSettings.defaults[3], enabled: true)[14], 0x2f)
    }

    func testMeterMessages() {
        XCTAssertEqual(h(Messages.meterInit1), "71 01 00 00")
        XCTAssertEqual(h(Messages.meterInit2(compChannel: 7)), "62 02 07 61 02 04 b1 01 00 00")
    }

    func testMeterParser() {
        var frame = [UInt8](repeating: 0, count: 64)
        // record 0: input channel 3 level 0x1234
        frame.replaceSubrange(4..<14, with: [0x61, 0x02, 0x04, 0x62, 0x02, 0x03, 0x72, 0x00, 0x34, 0x12])
        // record 1: compressor reduction on channel 1 = 0x0100
        frame.replaceSubrange(14..<24, with: [0x61, 0x02, 0x04, 0x62, 0x02, 0x01, 0xb2, 0x00, 0x00, 0x01])
        // record 2: master right = 0x7fff
        frame.replaceSubrange(24..<34, with: [0x61, 0x02, 0x02, 0x62, 0x02, 0x02, 0x72, 0x00, 0xff, 0x7f])
        var levels = MeterLevels()
        MeterParser.update(&levels, frame: frame)
        XCTAssertEqual(levels.input[2], 0x1234)
        XCTAssertEqual(levels.compReduction[0], 0x0100)
        XCTAssertEqual(levels.master[1], 0x7fff)
        XCTAssertEqual(levels.master[0], 0)
    }

    func testSyncMessagesCoverEverything() {
        let msgs = MixerState().syncMessages()
        // 8 routes + 4 master/bus + 16 * (4 + 4 EQ bands + 1 comp)
        XCTAssertEqual(msgs.count, 8 + 4 + 16 * 9)
        XCTAssertEqual(Set(msgs.map { $0.key }).count, msgs.count, "keys must be unique")
    }

    func testStateRoundTrip() throws {
        var s = MixerState()
        s.channels[3].faderDB = -20
        s.channels[3].comp.enabled = true
        s.routes[0] = 1
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(MixerState.self, from: data), s)
    }

    func testDryRunTransportRecords() throws {
        let t = DryRunTransport()
        t.printToStdout = false
        try t.send(Messages.mute(channel: 0, on: true))
        XCTAssertEqual(t.sent.count, 1)
    }
}
