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

import SwiftUI
import AppKit
import US16x08Core

final class AppModel: ObservableObject {
    @Published var state: MixerState
    @Published var status = "Not connected"
    @Published var connected = false
    /// True while the meter poller runs. Meters are always on while the unit is connected.
    @Published var metersOn = false
    /// Meter data and the log are kept OUT of the published state on purpose: publishing them made the
    /// whole window (menus, toolbar, DSP panel) re-render at USB polling speed, which burned CPU and
    /// made menus flicker. Meter views read `meterStore` on their own timer; only the Diagnostics
    /// window observes `logStore`.
    let meterStore = MeterStore()
    let logStore = LogStore()
    @Published var meterNote: String?
    @Published var conflictNote: String?
    @Published var selectedChannel = 0
    @Published var info = DeviceStatus()
    @Published var firmware: FirmwareInfo?
    @Published var scenes: [SceneSlot] = SceneStore.load()
    @Published var currentScene: Int?
    @Published var sceneNote: String?
    @Published var appearance: AppearanceMode = AppearanceMode.stored() {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: AppearanceMode.defaultsKey)
            appearance.apply()
        }
    }
    @Published var canPasteDSP = false
    private var dspClipboard: ChannelState?

    private var link: DeviceLink?
    private var watcher: DeviceWatcher?
    private var dryRunActive = false
    private var saveWork: DispatchWorkItem?
    private let flagsLock = NSLock()
    private var compFlags = [Bool](repeating: false, count: US16x08.channelCount)

    init() {
        state = StateStore.load() ?? MixerState()
        refreshCompFlags()
        // Follow the cable: update the status pane on unplug, reconnect on plug-in.
        watcher = DeviceWatcher { [weak self] attached in self?.usbChanged(attached) }
        // Pick up sample-rate changes made in Audio MIDI Setup when we return to the app.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.refreshInfo()
            self?.checkConflicts()
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.checkConflicts()
            }
        }
        checkConflicts()
    }

    /// Two programs polling the same unit at once (ours and TASCAM's) can make it stop answering.
    private static let originalPanelID = "com.teac.US-16x08_SettingsPanel"
    func checkConflicts() {
        let running = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == AppModel.originalPanelID }
        let note: String? = running ? "TASCAM's own panel is running. Two programs polling the unit at once can make it stop responding." : nil
        if note != conflictNote { conflictNote = note }
    }

    private func usbChanged(_ attached: Bool) {
        if attached {
            appendLog("USB: US-16x08 plugged in")
            guard !connected else { return }
            // Give the unit a moment to finish enumerating before we open it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                // connect() pushes the full remembered state, so the unit comes back exactly as shown.
                self.connect()
                if self.connected { self.status = "Reconnected. Panel settings restored to the unit." }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.refreshInfo() }
            }
        } else {
            appendLog("USB: US-16x08 unplugged")
            guard connected, !dryRunActive else { return }
            disconnect()
            info = DeviceStatus()
            status = "US-16x08 unplugged"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.refreshInfo() }
        }
    }

    // MARK: Connection
    func connect(dryRun: Bool = false) {
        disconnect()
        dryRunActive = dryRun
        do {
            let transport: US16x08Transport
            if dryRun {
                let t = DryRunTransport()
                t.printToStdout = false
                transport = t
            } else {
                transport = try USBTransport()
            }
            let l = DeviceLink(transport: transport)
            l.onLog = { [weak self] s in self?.appendLog(s) }
            l.onError = { [weak self] s in
                DispatchQueue.main.async {
                    self?.status = "Error: \(s)"
                    self?.appendLog("ERROR \(s)")
                }
            }
            l.onMeterStatus = { [weak self] status in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    switch status {
                    case .running:
                        self.meterNote = nil
                        self.appendLog("Meters recovered")
                    case .retrying(let why):
                        self.meterNote = "Unit not responding, retrying…"
                        self.appendLog("Meters paused: \(why)")
                    }
                }
            }
            l.compEnabledChannels = { [weak self] in self?.currentCompFlags() ?? [] }
            link = l
            connected = true
            status = dryRun ? "Dry-run (nothing is sent)" : "Connected to US-16x08"
        } catch {
            connected = false
            status = "\(error)"
        }
        refreshInfo()
        guard connected else { return }
        if dryRun { syncAll() } else { refreshFirmware(startSession: true) }
    }

    /// Firmware version/build via the unit's own query (read-only). With `startSession`, the full
    /// remembered state is pushed and metering starts once the query has finished, so none of the
    /// three interleave on the bus. (The unit can't be read back, so the app's state is the truth.)
    func refreshFirmware(startSession: Bool = false) {
        guard let l = link, connected else { return }
        DispatchQueue.global().async {
            do {
                let f = try l.readFirmware()
                DispatchQueue.main.async {
                    self.firmware = f
                    self.appendLog("Firmware: \(f.versionText ?? "?") raw \(f.versionRaw.map { String(format: "0x%04x", $0) } ?? "-") build \(f.buildRaw.map { String($0) } ?? "-")")
                }
            } catch {
                DispatchQueue.main.async { self.appendLog("Firmware query failed: \(error)") }
            }
            if startSession {
                DispatchQueue.main.async {
                    guard self.connected else { return }
                    self.syncAll()
                    if !self.metersOn { self.setMeters(true) }
                }
            }
        }
    }

    /// USB descriptors + Core Audio sample rate (no vendor protocol needed).
    func refreshInfo() {
        DispatchQueue.global().async {
            let s = DeviceInfo.query()
            DispatchQueue.main.async { self.info = s }
        }
    }

    // MARK: Scenes (stored on this Mac)
    func storeScene(_ i: Int) {
        scenes[i].state = state
        scenes[i].savedAt = Date()
        currentScene = i
        SceneStore.save(scenes)
    }
    func recallScene(_ i: Int) {
        guard let st = scenes[i].state else { return }
        state = st
        refreshCompFlags()
        changed()
        currentScene = i
        if connected { syncAll() }
    }
    /// Import one TASCAM scene file (a `US-16x08_smN` INI) into a slot.
    func importScene(file url: URL, into slot: Int) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            sceneNote = "Couldn't read \(url.lastPathComponent)."
            return
        }
        let (st, report) = OfficialScene.state(from: INIDocument(text: text))
        guard report.applied > 0 else { sceneNote = "\(url.lastPathComponent): \(report.summary)"; return }
        scenes[slot].state = st
        scenes[slot].savedAt = Date()
        SceneStore.save(scenes)
        sceneNote = "Imported \(url.lastPathComponent) into slot \(slot + 1). \(report.summary)"
        appendLog("Scene import: \(url.lastPathComponent) -> slot \(slot + 1). \(report.summary)")
    }

    /// Import every scene found in a folder (a copy of the official panel's settings folder, or one of our exports).
    func importSceneFolder(_ dir: URL) {
        let found = SceneStore.read(from: dir)
        let n = found.filter { $0.state != nil }.count
        guard n > 0 else { sceneNote = "No US-16x08_sm*.ini scene files found in \(dir.lastPathComponent)."; return }
        for s in found where s.state != nil { scenes[s.id] = s }
        SceneStore.save(scenes)
        sceneNote = "Imported \(n) scene\(n == 1 ? "" : "s") from \(dir.lastPathComponent)."
        appendLog("Scene import: \(n) from \(dir.path)")
    }

    func exportScenes(to dir: URL) {
        SceneStore.write(scenes, to: dir)
        sceneNote = "Exported to \(dir.lastPathComponent) in TASCAM's scene format."
    }

    func exportScene(_ slot: Int, to url: URL) {
        guard let st = scenes[slot].state else { return }
        do {
            try OfficialScene.document(from: st).text().write(to: url, atomically: true, encoding: .utf8)
            sceneNote = "Exported slot \(slot + 1) to \(url.lastPathComponent)."
        } catch { sceneNote = "Export failed: \(error.localizedDescription)" }
    }

    func renameScene(_ i: Int, _ name: String) {
        scenes[i].name = name
        SceneStore.save(scenes)
    }
    func clearScene(_ i: Int) {
        scenes[i].state = nil
        scenes[i].savedAt = nil
        if currentScene == i { currentScene = nil }
        SceneStore.save(scenes)
    }

    func disconnect() {
        link?.stopMeters()
        link = nil
        firmware = nil
        connected = false
        metersOn = false
        meterNote = nil
        meterStore.reset()
        status = "Not connected"
    }

    /// Pushes everything the panel shows to the unit. Automatic: on every connect, reconnect and
    /// scene recall. There is deliberately no manual "send all".
    private func syncAll() {
        let msgs = state.syncMessages()
        link?.sendSequence(msgs)
        appendLog("Sending full state (\(msgs.count) messages)…")
    }

    func resetState() {
        state = MixerState()
        refreshCompFlags()
        changed()
        if connected { syncAll() }
    }

    /// Poll rate: each tick is one of four protocol steps, so every meter refreshes about 12 times a
    /// second at 50 Hz. The UI redraws from the store at 30 fps on its own.
    private static let meterPollHz = 50.0

    func setMeters(_ on: Bool) {
        guard let link = link else { return }
        metersOn = on
        if on {
            meterStore.reset()
            appendLog("Meters on")
            let store = meterStore
            link.startMeters(hz: AppModel.meterPollHz) { levels in
                store.update(levels, now: Date.timeIntervalSinceReferenceDate)
            }
        } else {
            link.stopMeters()
            meterNote = nil
            meterStore.reset()
            appendLog("Meters off")
        }
    }

    func clearClip(input ch: Int) { meterStore.clearClip(input: ch) }
    func clearClip(master side: Int) { meterStore.clearClip(master: side) }
    func clearPeaks() { meterStore.clearPeaks() }

    // MARK: Channel controls
    func setFader(_ ch: Int, _ db: Int) {
        state.channels[ch].faderDB = db
        changed()
        link?.send(key: "fader\(ch)", Messages.fader(channel: ch, db: db))
    }
    func setPan(_ ch: Int, _ pos: Int) {
        state.channels[ch].pan = pos
        changed()
        link?.send(key: "pan\(ch)", Messages.pan(channel: ch, position: pos))
    }
    func setMute(_ ch: Int, _ on: Bool) {
        state.channels[ch].mute = on
        changed()
        link?.send(key: "mute\(ch)", Messages.mute(channel: ch, on: on))
    }
    func setPhase(_ ch: Int, _ on: Bool) {
        state.channels[ch].phase = on
        changed()
        link?.send(key: "phase\(ch)", Messages.phase(channel: ch, on: on))
    }

    // MARK: DSP
    func setEQEnabled(_ ch: Int, _ on: Bool) {
        state.channels[ch].eqEnabled = on
        changed()
        let c = state.channels[ch]
        link?.sendSequence((0..<4).map {
            OutboundMessage(key: "eq\(ch).\($0)", bytes: Messages.eqBand(channel: ch, band: $0, c.eq[$0], enabled: on))
        })
    }
    func updateEQ(_ ch: Int, band: Int, _ edit: (inout EQBandSettings) -> Void) {
        edit(&state.channels[ch].eq[band])
        changed()
        let c = state.channels[ch]
        link?.send(key: "eq\(ch).\(band)", Messages.eqBand(channel: ch, band: band, c.eq[band], enabled: c.eqEnabled))
    }
    /// Low-cut filter, as in the original panel: the LOW band pinned at -12 dB (gain restored when off).
    func setLowCut(_ ch: Int, _ on: Bool) {
        let current = state.channels[ch].eq[0].gain
        let restore = state.channels[ch].lowCutRestoreGain ?? 12
        state.channels[ch].lowCutRestoreGain = on ? current : nil
        updateEQ(ch, band: 0) { $0.gain = on ? 0 : restore }
    }
    /// High-cut (our own addition, not in the original): the HIGH shelf pinned at -12 dB.
    func setHighCut(_ ch: Int, _ on: Bool) {
        let current = state.channels[ch].eq[3].gain
        let restore = state.channels[ch].highCutRestoreGain ?? 12
        state.channels[ch].highCutRestoreGain = on ? current : nil
        updateEQ(ch, band: 3) { $0.gain = on ? 0 : restore }
    }
    func updateComp(_ ch: Int, _ edit: (inout CompressorSettings) -> Void) {
        edit(&state.channels[ch].comp)
        refreshCompFlags()
        changed()
        link?.send(key: "comp\(ch)", Messages.compressor(channel: ch, state.channels[ch].comp))
    }

    func copyDSP(_ ch: Int) {
        dspClipboard = state.channels[ch]
        canPasteDSP = true
    }
    func pasteDSP(_ ch: Int) {
        guard let src = dspClipboard else { return }
        state.channels[ch].eq = src.eq
        state.channels[ch].eqEnabled = src.eqEnabled
        state.channels[ch].lowCutRestoreGain = src.lowCutRestoreGain
        state.channels[ch].highCutRestoreGain = src.highCutRestoreGain
        state.channels[ch].comp = src.comp
        dspChanged(ch)
    }
    func resetDSP(_ ch: Int) {
        let blank = ChannelState(id: ch)
        state.channels[ch].eq = blank.eq
        state.channels[ch].eqEnabled = false
        state.channels[ch].lowCutRestoreGain = nil
        state.channels[ch].highCutRestoreGain = nil
        state.channels[ch].comp = blank.comp
        dspChanged(ch)
    }
    private func dspChanged(_ ch: Int) {
        refreshCompFlags()
        changed()
        let c = state.channels[ch]
        var msgs = (0..<4).map {
            OutboundMessage(key: "eq\(ch).\($0)", bytes: Messages.eqBand(channel: ch, band: $0, c.eq[$0], enabled: c.eqEnabled))
        }
        msgs.append(OutboundMessage(key: "comp\(ch)", bytes: Messages.compressor(channel: ch, c.comp)))
        link?.sendSequence(msgs)
    }

    // MARK: Master / routing
    func setMasterFader(_ db: Int) {
        state.masterFaderDB = db
        changed()
        link?.send(key: "masterFader", Messages.masterFader(db: db))
    }
    func setMasterMute(_ on: Bool) {
        state.masterMute = on
        changed()
        link?.send(key: "masterMute", Messages.masterMute(on: on))
    }
    func setBypass(_ on: Bool) {
        state.bypass = on
        changed()
        link?.send(key: "bypass", Messages.bypass(on: on))
    }
    func setBussOut(_ on: Bool) {
        state.bussOut = on
        changed()
        link?.send(key: "bussOut", Messages.bussOut(on: on))
    }
    func setRoute(_ output: Int, _ source: Int) {
        state.routes[output] = source
        changed()
        link?.send(key: "route\(output)", Messages.route(output: output, sourceIndex: source))
    }

    // MARK: Helpers
    /// Thread-safe: may be called from the USB queue.
    func appendLog(_ s: String) { logStore.append(s) }

    /// Everything needed to describe a problem, followed by the log.
    func diagnosticsReport() -> String {
        let bundle = Bundle.main.infoDictionary
        var out: [String] = []
        out.append("US-16x08 Panel \(bundle?["CFBundleShortVersionString"] as? String ?? "development build")")
        out.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        out.append("Connected: \(connected). \(status)")
        out.append("Device: \(info.productName ?? "-"), USB \(info.usbSpeed ?? "-"), release \(info.deviceRelease ?? "-")")
        out.append("Firmware: \(firmware?.summary ?? "-")")
        out.append("Sample rate: \(info.sampleRateText ?? "-")")
        out.append("Meters: \(metersOn ? "on" : "off")\(meterNote.map { ", " + $0 } ?? "")")
        if let c = conflictNote { out.append("Warning: \(c)") }
        out.append(String(repeating: "-", count: 60))
        return (out + logStore.snapshot()).joined(separator: "\n")
    }

    private func refreshCompFlags() {
        flagsLock.lock()
        compFlags = state.channels.map { $0.comp.enabled }
        flagsLock.unlock()
    }
    private func currentCompFlags() -> [Bool] {
        flagsLock.lock()
        defer { flagsLock.unlock() }
        return compFlags
    }

    /// Debounced save of the last-sent state.
    private func changed() {
        saveWork?.cancel()
        let snapshot = state
        let work = DispatchWorkItem { StateStore.save(snapshot) }
        saveWork = work
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
