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

final class InfoAndSceneTests: XCTestCase {
    func testInfoParsing() {
        var s = DeviceStatus()
        DeviceInfo.apply(infoText: "USB Product Name=US-16x08\nUSB Vendor Name=TASCAM\nbcdDevice=528\nDevice Speed=2\nUSB Serial Number=ABC123\n", to: &s)
        XCTAssertEqual(s.productName, "US-16x08")
        XCTAssertEqual(s.vendorName, "TASCAM")
        XCTAssertEqual(s.deviceRelease, "2.10")          // 528 == 0x0210
        XCTAssertEqual(s.usbSpeed, "High speed (480 Mbit/s)")
        XCTAssertEqual(s.serial, "ABC123")
    }

    func testSampleRateText() {
        var s = DeviceStatus()
        s.sampleRate = 44100
        XCTAssertEqual(s.sampleRateText, "44.1 kHz")
        s.sampleRate = 48000
        XCTAssertEqual(s.sampleRateText, "48 kHz")
    }

    func testSceneRoundTrip() throws {
        var slot = SceneSlot(id: 2)
        var st = MixerState()
        st.channels[0].faderDB = -12
        slot.state = st
        slot.savedAt = Date(timeIntervalSince1970: 1_000_000)
        let data = try JSONEncoder().encode([slot])
        XCTAssertEqual(try JSONDecoder().decode([SceneSlot].self, from: data), [slot])
        XCTAssertEqual(slot.name, "Scene 3")
    }
}

final class FirmwareTests: XCTestCase {
    func testVersionQueryBytes() {
        XCTAssertEqual(hexString(Messages.versionQuery), "31 01 00 00")
    }

    func testTLVParse() {
        let frame: [UInt8] = [0xA1, 0x03, 0x01, 0x00,  0x32, 0x03, 0xC8, 0x00,  0x33, 0x03, 0x7B, 0x00,
                              0x12, 0x05, 0x02, 0x68, 0x69,  0x00, 0x00, 0xFF]
        let items = TLV.parse(frame)
        XCTAssertEqual(items.map { $0.tag }, [0xA1, 0x32, 0x33, 0x12])
        XCTAssertEqual(items[3].value, [0x68, 0x69])
    }

    func testFirmwareExtract() {
        var info = FirmwareInfo()
        Firmware.extract(from: [0xA1, 0x03, 0x01, 0x00, 0x32, 0x03, 0xC8, 0x00, 0x33, 0x03, 0x7B, 0x00, 0x00, 0x00], into: &info)
        XCTAssertEqual(info.versionRaw, 200)
        XCTAssertEqual(info.versionText, "2.00")
        XCTAssertEqual(info.buildRaw, 123)
    }

    func testTLVStopsOnUnknownType() {
        XCTAssertEqual(TLV.parse([0x10, 0x09, 0x00, 0x00]).count, 0)
    }

    /// Real reply captured from a US-16x08 running firmware V2.00.
    func testRealFrameFromHardware() {
        let hex = "a1 03 01 00 32 03 c8 00 33 03 16 00 34 05 08 55 53 2d 31 36 78 30 38 35 05 0b 41 75 67 20 32 32 20 32 30 31 36 36 05 08 31 31 3a 30 33 3a 31 38 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"
        let frame = hex.split(separator: " ").map { UInt8($0, radix: 16)! }
        XCTAssertEqual(frame.count, 64)
        var info = FirmwareInfo()
        Firmware.extract(from: frame, into: &info)
        XCTAssertEqual(info.versionText, "2.00")
        XCTAssertEqual(info.buildRaw, 22)
        XCTAssertEqual(info.productName, "US-16x08")
        XCTAssertEqual(info.buildDate, "Aug 22 2016")
        XCTAssertEqual(info.buildTime, "11:03:18")
        XCTAssertEqual(info.displayText, "2.00 0022")      // matches the original panel's Interface page
        XCTAssertEqual(info.summary, "2.00 0022 · Aug 22 2016 11:03:18")
    }
}

final class MeterScaleTests: XCTestCase {
    func testLevelScaleMatchesHardwareMeasurements() {
        XCTAssertEqual(MeterScale.dBFS(32767)!, 0, accuracy: 0.001)
        XCTAssertEqual(MeterScale.dBFS(2146)!, -23.7, accuracy: 0.1)    // -24 dBFS tone, measured
        XCTAssertEqual(MeterScale.dBFS(15814)!, -6.3, accuracy: 0.1)
        XCTAssertNil(MeterScale.dBFS(0))
    }

    func testReductionScale() {
        XCTAssertEqual(MeterScale.reductionDB(1740), 25.5, accuracy: 0.1) // output dropped 25.3 dB, measured
        XCTAssertEqual(MeterScale.reductionDB(32767), 0, accuracy: 0.001)
        XCTAssertEqual(MeterScale.reductionDB(0), 0)
    }
}

final class PeakTests: XCTestCase {
    func testPeakHoldsThenFalls() {
        var p = MeterPeaks()
        var l = MeterLevels()
        l.input[0] = 10000
        p.update(l, now: 0)
        XCTAssertEqual(p.input[0].peak, 10000)
        l.input[0] = 100
        p.update(l, now: 1.0)                       // inside the 1.5 s hold
        p.update(l, now: 1.4)
        XCTAssertEqual(p.input[0].peak, 10000)
        p.update(l, now: 1.9)                       // 0.5 s step after the hold: 20 dB/s -> -10 dB
        XCTAssertEqual(p.input[0].peak, 10000 * pow(10.0, -0.5), accuracy: 1)
    }

    func testClipLatchesUntilCleared() {
        var p = MeterPeaks()
        var l = MeterLevels()
        l.master[1] = 32765                          // what a clipping input read on real hardware
        p.update(l, now: 0)
        XCTAssertTrue(p.master[1].clipped)
        XCTAssertFalse(p.master[0].clipped)
        l.master[1] = 0
        p.update(l, now: 5)
        XCTAssertTrue(p.master[1].clipped)
        p.clearAll()
        XCTAssertFalse(p.master[1].clipped)
    }

    func testQuietSignalDoesNotClip() {
        var p = MeterPeaks()
        var l = MeterLevels()
        l.input[3] = 20000
        p.update(l, now: 0)
        XCTAssertFalse(p.input[3].clipped)
    }
}

final class EQTableTests: XCTestCase {
    func testManualDefaultsLandOnTheDeviceDefaults() {
        // Reference Manual defaults vs the device's own default steps (0x05, 0x0e, 0x1b, 0x0f).
        XCTAssertEqual(EQTables.hz(band: 0, step: 0x05), 80)
        XCTAssertEqual(EQTables.hz(band: 1, step: 0x0e), 300)
        XCTAssertEqual(EQTables.hz(band: 2, step: 0x1b), 1200)
        XCTAssertEqual(EQTables.hz(band: 3, step: 0x0f), 5000)
        XCTAssertEqual(EQTables.qValues[EQBandSettings.defaults[1].width], 1.0)
    }

    func testTableShapeAndRanges() {
        XCTAssertEqual(EQTables.freqTable.count, 64)
        XCTAssertEqual(EQTables.freqTable, EQTables.freqTable.sorted())
        XCTAssertEqual(Set(EQTables.freqTable).count, 64)
        XCTAssertEqual(EQTables.hz(band: 0, step: 0), 32)
        XCTAssertEqual(EQTables.hz(band: 0, step: 31), 1600)
        XCTAssertEqual(EQTables.hz(band: 1, step: 63), 18000)
        XCTAssertEqual(EQTables.hz(band: 3, step: 0), 1700)
        XCTAssertEqual(EQTables.hz(band: 3, step: 31), 18000)
    }

    func testStepRoundTrip() {
        for band in 0..<4 {
            for step in EQBandSettings.frequencyRange(band: band) {
                XCTAssertEqual(EQTables.step(band: band, nearestTo: EQTables.hz(band: band, step: step)), step)
            }
        }
    }

    func testLabels() {
        XCTAssertEqual(EQTables.label(hz: 80), "80 Hz")
        XCTAssertEqual(EQTables.label(hz: 1200), "1.2 kHz")
        XCTAssertEqual(EQTables.label(hz: 18000), "18.0 kHz")
        XCTAssertEqual(EQTables.qLabel(2), "1.00")
        XCTAssertEqual(CompressorSettings.ratioLabel(14), "∞:1")
        XCTAssertEqual(CompressorSettings.ratioLabel(13), "16.0:1")
    }

    func testFilterShapes() {
        var bands = EQBandSettings.defaults
        bands[1] = EQBandSettings(gain: 24, frequency: 25, width: 2)           // +12 dB bell at 1 kHz, Q 1
        XCTAssertEqual(EQResponse.magnitudeDB(bands: bands, atHz: 1000), 12, accuracy: 0.2)
        XCTAssertEqual(EQResponse.magnitudeDB(bands: bands, atHz: 20000), 0, accuracy: 0.5)
        var shelf = EQBandSettings.defaults
        shelf[0].gain = 24                                                       // +12 dB low shelf at 80 Hz
        XCTAssertEqual(EQResponse.magnitudeDB(bands: shelf, atHz: 20), 12, accuracy: 0.3)
        XCTAssertEqual(EQResponse.magnitudeDB(bands: shelf, atHz: 5000), 0, accuracy: 0.3)
        XCTAssertEqual(EQResponse.magnitudeDB(bands: EQBandSettings.defaults, atHz: 1000), 0, accuracy: 0.001)
    }
}

final class CompressorManualTests: XCTestCase {
    func testDefaultsMatchTheReferenceManual() {
        let c = CompressorSettings()
        XCTAssertFalse(c.enabled)
        XCTAssertEqual(c.thresholdDB, 0)                                     // 0 dB
        XCTAssertEqual(CompressorSettings.ratioLabel(c.ratioIndex), "1.0:1") // 1.0:1
        XCTAssertEqual(c.gainDB, 0)                                          // 0 dB
        XCTAssertEqual(c.attackMS, 2)                                        // 2 ms
        XCTAssertEqual(c.releaseMS, 10)                                      // 10 ms
    }

    func testRangesMatchTheReferenceManual() {
        XCTAssertEqual(CompressorSettings.thresholdRange, -32...0)
        XCTAssertEqual(CompressorSettings.gainRange, 0...20)
        XCTAssertEqual(CompressorSettings.attackRange, 2...200)
        XCTAssertEqual(CompressorSettings.releaseRange, 10...1000)
        XCTAssertEqual(CompressorSettings.ratioLabel(0), "1.0:1")
        XCTAssertEqual(CompressorSettings.ratioLabel(Messages.ratioTable.count - 1), "∞:1")
    }

    func testOutOfRangeValuesAreClampedOnTheWire() {
        var c = CompressorSettings()
        c.enabled = true
        c.thresholdDB = -99
        c.ratioIndex = 99
        c.attackMS = 500
        c.releaseSteps = 0
        c.gainDB = 99
        XCTAssertEqual(hexString(Messages.compressor(channel: 0, c)),
                       "61 02 04 62 02 01 91 02 e0 92 02 ff 93 02 c8 94 02 01 95 02 14 96 02 01 97 02 01 00 00")
    }
}

final class MeterStoreTests: XCTestCase {
    func testStoreReportsLevelsPeaksAndClips() {
        let store = MeterStore()
        var l = MeterLevels()
        l.input[2] = 32765
        l.master[0] = 5000
        l.compReduction[2] = 1740
        store.update(l, now: 0)
        XCTAssertEqual(store.input(2).level, 32765)
        XCTAssertTrue(store.input(2).clipped)
        XCTAssertEqual(store.master(0).level, 5000)
        XCTAssertFalse(store.master(0).clipped)
        XCTAssertEqual(store.compReduction(2), 1740)
        store.clearClip(input: 2)
        XCTAssertFalse(store.input(2).clipped)
        store.reset()
        XCTAssertEqual(store.input(2).level, 0)
        XCTAssertEqual(store.input(99).level, 0)          // out of range is safe
    }

    func testNotRespondingErrorIsReadable() {
        let e = TransportError.transfer(code: Int32(bitPattern: 0xe00002ed), what: "send")
        XCTAssertTrue("\(e)".contains("not responding"), "\(e)")
    }
}

final class ControlLogicTests: XCTestCase {
    func testFaderTaper() {
        XCTAssertEqual(FaderTaper.position(db: 0), 0.80, accuracy: 0.0001)
        XCTAssertEqual(FaderTaper.position(db: 6), 1.0, accuracy: 0.0001)
        XCTAssertEqual(FaderTaper.position(db: -127), 0.0, accuracy: 0.0001)
        XCTAssertEqual(FaderTaper.db(position: 0.80), 0)
        XCTAssertEqual(FaderTaper.db(position: 1.0), 6)
        XCTAssertEqual(FaderTaper.db(position: 0.0), -127)
        XCTAssertEqual(FaderTaper.db(position: 0.01), -127)
        var last = -1000
        for step in 0...100 {                                  // monotonic
            let d = FaderTaper.db(position: Double(step) / 100)
            XCTAssertGreaterThanOrEqual(d, last)
            last = d
        }
        for db in [-60, -40, -30, -20, -10, -3, 0, 3, 6] {      // round trip
            XCTAssertEqual(FaderTaper.db(position: FaderTaper.position(db: db)), db)
        }
    }

    func testTypedValues() {
        XCTAssertEqual(ValueParsing.integer("+4"), 4)
        XCTAssertEqual(ValueParsing.integer("\u{2212}2 dB"), -2)
        XCTAssertEqual(ValueParsing.integer("-18"), -18)
        XCTAssertNil(ValueParsing.integer("abc"))
        XCTAssertEqual(ValueParsing.frequencyHz("1.2k"), 1200)
        XCTAssertEqual(ValueParsing.frequencyHz("300 Hz"), 300)
        XCTAssertEqual(ValueParsing.frequencyHz("5 kHz"), 5000)
        XCTAssertEqual(ValueParsing.frequencyHz("1.2"), 1200)       // below 20 means kHz
        XCTAssertEqual(ValueParsing.ratioIndex("3"), 7)
        XCTAssertEqual(ValueParsing.ratioIndex("3.0:1"), 7)
        XCTAssertEqual(ValueParsing.ratioIndex("inf"), 14)
        XCTAssertEqual(ValueParsing.ratioIndex("16"), 13)
        XCTAssertEqual(ValueParsing.qIndex("1"), 2)
        XCTAssertEqual(ValueParsing.qIndex("0.3"), 0)
        // a typed frequency lands on the nearest device step
        XCTAssertEqual(EQTables.step(band: 2, nearestTo: ValueParsing.frequencyHz("1.2k")!), 27)
    }

    func testOlderSavedStateStillDecodes() throws {
        // A channel saved before LCF/HCF existed has no such keys.
        let json = #"{"id":3,"faderDB":-6,"pan":0,"mute":false,"phase":false,"eqEnabled":false,"eq":[{"gain":12,"frequency":5,"width":2},{"gain":12,"frequency":14,"width":2},{"gain":12,"frequency":27,"width":2},{"gain":12,"frequency":15,"width":2}],"comp":{"enabled":false,"thresholdDB":0,"ratioIndex":0,"attackMS":2,"releaseSteps":1,"gainDB":0}}"#
        let ch = try JSONDecoder().decode(ChannelState.self, from: Data(json.utf8))
        XCTAssertNil(ch.lowCutRestoreGain)
        XCTAssertEqual(ch.faderDB, -6)
    }
}

