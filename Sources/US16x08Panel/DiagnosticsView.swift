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

/// The diagnostics log, in its own window (Window menu, Option-Command-L).
struct DiagnosticsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        DiagnosticsList(store: model.logStore)
    }
}

private struct DiagnosticsList: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var store: LogStore

    var body: some View {
        let lines = store.snapshot()
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.connected ? Color.green : Color.red)
                    .frame(width: 9, height: 9)
                Text(model.status).font(.callout).lineLimit(1)
                Spacer()
                Button("Copy All") { copyAll() }
                Button("Save…") { save() }
                Button("Clear") { store.clear() }
            }
            if let note = model.meterNote ?? model.conflictNote {
                Text(note).font(.caption).foregroundStyle(.orange)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: store.revision) { _, _ in
                    if !lines.isEmpty { proxy.scrollTo(lines.count - 1, anchor: .bottom) }
                }
            }
            Text("Everything sent to the unit, errors and state changes. Use Copy All or Save when reporting a problem.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.diagnosticsReport(), forType: .string)
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "us16x08-diagnostics.txt"
        let text = model.diagnosticsReport()
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? text.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
