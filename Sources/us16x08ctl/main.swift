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

// us16x08ctl — hardware bring-up tool for the unofficial US-16x08 panel.
// Usage: us16x08ctl [--dry-run] <command> [args]   (see `help`)

let usage = """
us16x08ctl — unofficial TASCAM US-16x08 control tool

  list                          list all USB devices (look for 0644:8047)
  info                          USB descriptor + Core Audio details (read-only)
  firmware                      read firmware version/build from the unit (read-only query)
  probe                         read ONE meter frame (read-only, safest first test)
  meters [seconds]              live meter display (default 5 s)
  selftest                      guided, interactive hardware test -> writes a report
  autotest [--level=-24] [--yes]  automated: the Mac plays test tones, the unit's meters verify
                                (plays audio! turn monitors down; optional cable LINE OUT 8 -> LINE IN 16)
  dump                          print example messages (no hardware needed)

  fader <ch 1-16> <dB -127..6>      pan <ch> <-127..127>
  mute <ch> <0|1>                   phase <ch> <0|1>
  master-fader <dB>                 master-mute <0|1>
  bypass <0|1>   (Mixer True Bypass)    bus-out <0|1>   (Computer out to Stereo BUS)
  route <out 1-8> <src 0-9>         (0/1 = master L/R, 2-9 = computer 1-8)
  eq-enable <ch> <0|1>              eq <ch> <band 1-4> <gain 0-24> <freq> [width 0-6]
  comp <ch> <on 0|1> <thr -32..0> <ratio 0-14> <attack 2-200> <release 1-100> <gain 0-20>

Options:
  --dry-run                     print bytes instead of sending them
  --kernel-high-freq            send high-band EQ freq exactly like the Linux driver (no +0x20)
"""

let levelArg = CommandLine.arguments.first { $0.hasPrefix("--level=") }.flatMap { Double($0.dropFirst(8)) } ?? -24.0
let assumeYes = CommandLine.arguments.contains("--yes")
var args = Array(CommandLine.arguments.dropFirst())
let dry = args.contains("--dry-run")
if args.contains("--kernel-high-freq") { Messages.highBandFrequencyOffset = 0 }
args.removeAll { $0.hasPrefix("--") }

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(1)
}

func intArg(_ i: Int, _ name: String) -> Int {
    guard i < args.count, let v = Int(args[i]) else { fail("missing/invalid <\(name)>\n\n\(usage)") }
    return v
}

func makeLink() -> DeviceLink {
    if dry { return DeviceLink(transport: DryRunTransport()) }
    do { return DeviceLink(transport: try USBTransport()) }
    catch { fail("\(error)") }
}

func sendNow(_ link: DeviceLink, _ bytes: [UInt8]) {
    link.onLog = { print($0) }
    link.onError = { print("ERROR: \($0)") }
    link.send(key: "cli", bytes)
    Thread.sleep(forTimeInterval: 0.3)     // let the coalescing queue flush
}

guard let command = args.first else { print(usage); exit(0) }

switch command {
case "help", "-h":
    print(usage)

case "list":
    print(USBTransport.listDevices())
    print("Looking for 0644:8047 (TASCAM US-16x08).")

case "dump":
    let samples: [(String, [UInt8])] = [
        ("fader ch1 0 dB", Messages.fader(channel: 0, db: 0)),
        ("mute ch4 on", Messages.mute(channel: 3, on: true)),
        ("master fader -10 dB", Messages.masterFader(db: -10)),
        ("route out1 <- master R", Messages.route(output: 0, sourceIndex: 1)),
        ("compressor ch1 defaults", Messages.compressor(channel: 0, CompressorSettings())),
        ("eq ch1 low band defaults", Messages.eqBand(channel: 0, band: 0, EQBandSettings.defaults[0], enabled: false)),
    ]
    for (n, b) in samples { print(n.padding(toLength: 28, withPad: " ", startingAt: 0), hexString(b)) }

case "info":
    let i = DeviceInfo.query()
    print("Detected on USB : \(i.present)")
    print("Product         : \(i.productName ?? "-")")
    print("Manufacturer    : \(i.vendorName ?? "-")")
    print("Serial          : \(i.serial ?? "-")")
    print("USB speed       : \(i.usbSpeed ?? "-")")
    print("Device release  : \(i.deviceRelease ?? "-")  (bcdDevice; firmware match unconfirmed)")
    print("Core Audio      : \(i.audioDeviceName ?? "-")  \(i.sampleRateText ?? "")")
    if i.present, !dry, let t = try? USBTransport(), let f = try? DeviceLink(transport: t).readFirmware() {
        print("Firmware        : \(f.summary ?? "-")")
    }

case "firmware":
    let link = makeLink()
    do {
        let f = try link.readFirmware()
        print("Ready tag (0xA1) seen : \(f.readyTagSeen)")
        print("Version raw           : \(f.versionRaw.map { String(format: "0x%04x", $0) } ?? "-")")
        print("Firmware (as shown by the original panel): \(f.displayText ?? "-")")
        print("Version               : \(f.versionText ?? "-")   (raw is decimal x100)")
        print("Product (from unit)   : \(f.productName ?? "-")")
        print("Build date / time     : \(f.buildDate ?? "-") \(f.buildTime ?? "")")
        print("Build raw             : \(f.buildRaw.map { String($0) } ?? "-")")
        print("Last frame            : \(hexString(f.lastFrame))")
    } catch { fail("\(error)") }

case "probe":
    let link = makeLink()
    do {
        let frame = try link.probeMeterFrame()
        print("Meter frame (\(frame.count) bytes):")
        print(hexString(frame))
        var levels = MeterLevels()
        MeterParser.update(&levels, frame: frame)
        let recognised = (0..<6).filter { s in
            let b = s * 10 + 4
            return b + 3 < frame.count && frame[b] == 0x61 && frame[b + 1] == 0x02 && frame[b + 3] == 0x62
        }.count
        print("Recognised \(recognised) of 6 meter records.")
        print(recognised > 0 ? "PASS: device speaks the documented protocol." : "UNEXPECTED: no meter records recognised. Send me the hex above.")
    } catch { fail("\(error)") }

case "meters":
    let seconds = args.count > 1 ? (Double(args[1]) ?? 5) : 5
    let link = makeLink()
    link.onError = { print("ERROR: \($0)") }
    var peak = MeterLevels()
    let lock = NSLock()
    var latest = MeterLevels()
    link.startMeters(hz: 60) { l in lock.lock(); latest = l; lock.unlock() }
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        Thread.sleep(forTimeInterval: 0.25)
        lock.lock(); let l = latest; lock.unlock()
        for i in 0..<16 { peak.input[i] = max(peak.input[i], l.input[i]) }
        let bars = l.input.map { v -> String in
            let n = min(8, Int((Double(v) / Double(MeterLevels.maxValue)) * 8.0 * 3))
            return String(repeating: "#", count: n).padding(toLength: 8, withPad: ".", startingAt: 0)
        }
        print("\r" + bars.prefix(8).joined(separator: " "), terminator: "")
        fflush(stdout)
    }
    link.stopMeters()
    print("\nPeak raw input levels (0..32767): \(peak.input)")
    let peakDB = peak.input.map { raw in MeterScale.dBFS(raw).map { String(format: "%.1f", $0) } ?? "-inf" }
    print("Peak input levels (dBFS): \(peakDB)")

case "fader":        sendNow(makeLink(), Messages.fader(channel: intArg(1, "ch") - 1, db: intArg(2, "dB")))
case "pan":          sendNow(makeLink(), Messages.pan(channel: intArg(1, "ch") - 1, position: intArg(2, "pos")))
case "mute":         sendNow(makeLink(), Messages.mute(channel: intArg(1, "ch") - 1, on: intArg(2, "0|1") != 0))
case "phase":        sendNow(makeLink(), Messages.phase(channel: intArg(1, "ch") - 1, on: intArg(2, "0|1") != 0))
case "master-fader": sendNow(makeLink(), Messages.masterFader(db: intArg(1, "dB")))
case "master-mute":  sendNow(makeLink(), Messages.masterMute(on: intArg(1, "0|1") != 0))
case "bypass":       sendNow(makeLink(), Messages.bypass(on: intArg(1, "0|1") != 0))
case "bus-out":      sendNow(makeLink(), Messages.bussOut(on: intArg(1, "0|1") != 0))
case "route":        sendNow(makeLink(), Messages.route(output: intArg(1, "out") - 1, sourceIndex: intArg(2, "src")))

case "eq-enable":
    // The device wants the switch repeated in each band message.
    let ch = intArg(1, "ch") - 1
    let on = intArg(2, "0|1") != 0
    let link = makeLink()
    link.onLog = { print($0) }
    link.onError = { print("ERROR: \($0)") }
    link.sendSequence((0..<4).map {
        OutboundMessage(key: "eq\($0)", bytes: Messages.eqBand(channel: ch, band: $0, EQBandSettings.defaults[$0], enabled: on))
    })
    Thread.sleep(forTimeInterval: 0.3)

case "eq":
    let b = intArg(2, "band") - 1
    var s = EQBandSettings.defaults[min(max(b, 0), 3)]
    s.gain = intArg(3, "gain")
    s.frequency = intArg(4, "freq")
    if args.count > 5 { s.width = intArg(5, "width") }
    sendNow(makeLink(), Messages.eqBand(channel: intArg(1, "ch") - 1, band: b, s, enabled: true))

case "comp":
    var c = CompressorSettings()
    c.enabled = intArg(2, "on") != 0
    c.thresholdDB = intArg(3, "thr"); c.ratioIndex = intArg(4, "ratio")
    c.attackMS = intArg(5, "attack"); c.releaseSteps = intArg(6, "release"); c.gainDB = intArg(7, "gain")
    sendNow(makeLink(), Messages.compressor(channel: intArg(1, "ch") - 1, c))

case "selftest":
    runSelfTest(dry: dry)

case "autotest":
    if dry { fail("autotest needs the real device (it plays audio and reads meters).") }
    runAutoTest(level: levelArg, assumeYes: assumeYes)

default:
    fail("unknown command '\(command)'\n\n\(usage)")
}
