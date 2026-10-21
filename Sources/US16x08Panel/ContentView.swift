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

enum PanelSection: String, CaseIterable, Identifiable {
    case mixer = "Mixer"
    case routing = "Routing"
    case interface = "Interface"
    case scenes = "Scenes"
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var section: PanelSection = .mixer

    var body: some View {
        detail
            .frame(minWidth: Layout.minWidth, minHeight: Layout.minHeight)
            .background(WindowChrome())
            .toolbar {
                // Same recipe as Safari: tabs on the left, flexible space, a centred status chip, flexible space,
                // then the trailing controls. (ToolbarSpacer needs macOS 26, which Golden Gate is built on.)
                ToolbarItem(placement: .navigation) { sectionPicker }
                ToolbarSpacer(.flexible)
                ToolbarItem(placement: .principal) { StatusChip() }
                ToolbarSpacer(.flexible)
                ToolbarItem(placement: .primaryAction) { sceneMenu }
                ToolbarItem(placement: .primaryAction) { appearanceMenu }
                ToolbarSpacer(.fixed)
                ToolbarItem(placement: .primaryAction) { bypassSwitch }
            }
    }

    private var sectionPicker: some View {
        Picker("Section", selection: $section) {
            ForEach(PanelSection.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 300)
    }

    private var sceneMenu: some View {
        Menu {
            ForEach(model.scenes) { slot in
                Button(slot.name) { model.recallScene(slot.id) }.disabled(slot.state == nil)
            }
            Divider()
            Button("Manage Scenes…") { section = .scenes }
        } label: {
            Label(model.currentScene.map { model.scenes[$0].name } ?? "Scene", systemImage: "square.stack")
                .labelStyle(.titleAndIcon)
        }
        .help("Recall a stored scene (sends all values to the unit)")
    }

    private var appearanceMenu: some View {
        Menu {
            Picker("Appearance", selection: Binding(get: { model.appearance }, set: { model.appearance = $0 })) {
                ForEach(AppearanceMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Appearance", systemImage: model.appearance.symbol)
        }
        .help("Appearance: Auto follows the system")
    }

    private var bypassSwitch: some View {
        HStack(spacing: 8) {
            Text("True Bypass").font(.system(size: 12)).foregroundStyle(model.connected ? .primary : .secondary)
            Toggle("True Bypass", isOn: Binding(get: { model.state.bypass }, set: { model.setBypass($0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
        .fixedSize()
        .padding(.horizontal, 10)          // room inside the glass capsule the toolbar draws around the item
        .disabled(!model.connected)
        .help(model.connected ? "Mixer True Bypass: input and output matched binary, mixer processing skipped"
                              : "Connect the unit to change Mixer True Bypass")
    }

    @ViewBuilder
    private var detail: some View {
        switch section {
        case .mixer: MixerScreen()
        case .routing: RoutingScreen()
        case .interface: InterfaceScreen()
        case .scenes: ScenesScreen()
        }
    }
}

/// The window keeps its title (Mission Control, Window menu) but doesn't draw it.
struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { WindowChrome.configure(v.window) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { WindowChrome.configure(nsView.window) }
    }

    static func configure(_ w: NSWindow?) {
        guard let w else { return }
        w.titleVisibility = .hidden
    }
}

/// Title-bar status: light + device name. Details (rate, firmware, USB, status) are a click away,
/// paged like a small carousel, and the hover tip carries the one-line summary.
struct StatusChip: View {
    @EnvironmentObject var model: AppModel
    @State private var open = false

    private var summary: String {
        var parts = [model.connected ? "Connected" : "Not connected"]
        if let r = model.info.formatText { parts.append(r) }
        if let f = model.firmware?.displayText { parts.append("FW \(f)") }   // hover only; not shown in the title bar
        return parts.joined(separator: " · ")
    }

    /// "US-16x08 · 44.1 kHz · FW 2.00 0022" while connected, as in the mockup.
    private var chipText: String {
        var parts = [model.info.productName ?? "US-16x08"]
        if model.connected {
            if let r = model.info.sampleRateText { parts.append(r) }
            if let f = model.firmware?.displayText { parts.append("FW \(f)") }
        } else {
            parts.append("Not connected")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                Circle().fill(model.connected ? Color.green : Color.red).frame(width: 8, height: 8)
                Text(chipText).font(.system(size: 12, weight: .medium))
                if model.meterNote != nil || model.conflictNote != nil {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.system(size: 10))
                }
            }
        }
        .help(summary)
        .popover(isPresented: $open, arrowEdge: .bottom) { StatusPages().environmentObject(model) }
        .accessibilityLabel("Device status: \(summary)")
    }
}

struct StatusPages: View {
    @EnvironmentObject var model: AppModel
    @State private var page = 0

    private struct Page { let title: String; let rows: [(String, String)] }

    private var pages: [Page] {
        let i = model.info
        var out: [Page] = [
            Page(title: "Device", rows: [
                ("Name", i.productName ?? "US-16x08"),
                ("Connection", model.connected ? "Connected" : "Not connected"),
                ("USB", i.usbSpeed ?? "–"),
                ("Release", i.deviceRelease ?? "–"),
            ]),
            Page(title: "Audio", rows: [
                ("Sample rate", i.sampleRateText ?? "–"),
                ("Bit depth", i.bitDepth.map { "\($0)-bit" } ?? "–"),
                ("macOS offers", i.supportedRatesText ?? "–"),
                ("Unit supports", "44.1, 48, 88.2, 96 kHz · 16/24-bit"),
                ("Meters", model.metersOn ? "Running" : "Off"),
            ]),
            Page(title: "Firmware", rows: [
                ("Version", model.firmware?.displayText ?? "–"),
            ]),
            Page(title: "Status", rows: [
                ("Last event", model.status),
                ("Scene", model.currentScene.map { model.scenes[$0].name } ?? "–"),
            ]),
        ]
        if let n = model.meterNote { out[3] = Page(title: "Status", rows: out[3].rows + [("Meters", n)]) }
        if let c = model.conflictNote { out[3] = Page(title: "Status", rows: out[3].rows + [("Warning", c)]) }
        return out
    }

    var body: some View {
        let all = pages
        let p = all[min(page, all.count - 1)]
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { page = (page + all.count - 1) % all.count } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(p.title).font(.headline)
                Spacer()
                Button { page = (page + 1) % all.count } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.borderless)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                ForEach(p.rows, id: \.0) { row in
                    GridRow {
                        Text(row.0).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        Text(row.1).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.callout)
            HStack(spacing: 5) {
                ForEach(0..<all.count, id: \.self) { n in
                    Circle().fill(n == page ? Color.primary : Color.secondary.opacity(0.3)).frame(width: 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity)
            Divider()
            HStack {
                Button("Reconnect") { model.connect() }
                Spacer()
                Button("Disconnect") { model.disconnect() }.disabled(!model.connected)
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 280)
    }
}
