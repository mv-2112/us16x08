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

final class OfficialSceneTests: XCTestCase {
    func testINIParseAndWrite() {
        let doc = INIDocument(text: "[Track1]\nMute=true\nFader_value=-10\nCompRatioText=\"4.0:1\"\n\n[Misc]\nMixerTrueBypass=false\n")
        XCTAssertEqual(doc.bool("Track1", "Mute"), true)
        XCTAssertEqual(doc.int("Track1", "Fader_value"), -10)
        XCTAssertEqual(doc[group: "Track1", key: "CompRatioText"], "4.0:1")
        XCTAssertEqual(INIDocument(text: doc.text()), doc)
    }

    func testInfinityFader() {
        let doc = INIDocument(text: "[Track2]\nFader_value=-inf\n")
        XCTAssertEqual(doc.int("Track2", "Fader_value", infinity: -127), -127)
    }

    func testRoundTrip() {
        var s = MixerState()
        s.channels[2].mute = true
        s.channels[2].faderDB = -12
        s.channels[2].pan = 40
        s.channels[2].eqEnabled = true
        s.channels[2].eq[3].gain = 17
        s.channels[2].eq[3].frequency = 9
        s.channels[2].eq[1].width = 4
        s.channels[2].comp.enabled = true
        s.channels[2].comp.thresholdDB = -20
        s.channels[2].comp.ratioIndex = 6
        s.channels[2].comp.gainDB = 5
        s.channels[2].comp.attackMS = 40
        s.channels[2].comp.releaseSteps = 25
        s.masterFaderDB = -3
        s.bypass = true
        s.bussOut = false
        s.routes[3] = 7
        let (back, report) = OfficialScene.state(from: INIDocument(text: OfficialScene.document(from: s).text()))
        XCTAssertGreaterThan(report.applied, 100)
        XCTAssertEqual(back.channels[2].mute, true)
        XCTAssertEqual(back.channels[2].faderDB, -12)
        XCTAssertEqual(back.channels[2].pan, 40)
        XCTAssertEqual(back.channels[2].eq, s.channels[2].eq)
        XCTAssertEqual(back.channels[2].comp, s.channels[2].comp)
        XCTAssertEqual(back.masterFaderDB, -3)
        XCTAssertTrue(back.bypass)
        XCTAssertFalse(back.bussOut)
        XCTAssertEqual(back.routes[3], 7)
    }

    func testNamesFile() {
        let names = (0..<10).map { "Scene \($0 + 1)" }
        var n = names; n[4] = "Band"
        let parsed = OfficialScene.names(from: INIDocument(text: OfficialScene.namesDocument(n).text()))
        XCTAssertEqual(parsed[4], "Band")
        XCTAssertEqual(parsed.count, 10)
    }

    func testRejectsForeignFile() {
        let (_, report) = OfficialScene.state(from: INIDocument(text: "[Foo]\nBar=1\n"))
        XCTAssertEqual(report.applied, 0)
    }
}
