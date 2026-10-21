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

/// Ten named scenes, stored on this Mac. Recalling one sends every value to the unit.
struct ScenesScreen: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Scenes are stored on this Mac in TASCAM's own scene-file format, not in the unit. Recalling one updates the panel and sends every value to the device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Import folder…") { importFolder() }
                    .help("Import all scenes from a folder containing US-16x08_sm1…10 files, e.g. a copy of the official panel's settings")
                Button("Export all…") { exportAll() }
                    .help("Write US-16x08_sm1…10 and US-16x08_SceneMemory files into a folder you choose")
                Button("Show Folder") { NSWorkspace.shared.activateFileViewerSelecting([SceneStore.folderURL]) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            if let note = model.sceneNote {
                Text(note).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).textSelection(.enabled)
            }
            List {
                ForEach(model.scenes) { slot in
                    row(slot)
                }
            }
        }
    }

    private func row(_ slot: SceneSlot) -> some View {
        HStack(spacing: 10) {
            Text("\(slot.id + 1)").font(.headline).frame(width: 24)
            TextField("Name", text: Binding(get: { slot.name }, set: { model.renameScene(slot.id, $0) }))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
            Text(slot.savedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Empty")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if model.currentScene == slot.id {
                Label("Current", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
            Button("Store") { model.storeScene(slot.id) }
                .help("Save the current panel state into this slot")
            Button("Recall") { model.recallScene(slot.id) }
                .disabled(slot.state == nil)
            Button("Import…") { importFile(into: slot.id) }
                .help("Replace this slot with a TASCAM scene file (US-16x08_smN)")
            Button("Export…") { exportFile(slot) }
                .disabled(slot.state == nil)
                .help("Save this slot as a TASCAM-format scene file")
            Button {
                model.clearScene(slot.id)
            } label: {
                Image(systemName: "trash")
            }
            .disabled(slot.state == nil)
            .help("Clear this slot")
        }
        .padding(.vertical, 2)
    }

    // MARK: File panels

    private var officialFolder: URL? {
        let u = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/TASCAM")
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    private func importFile(into slot: Int) {
        let p = NSOpenPanel()
        p.message = "Choose a TASCAM scene file (US-16x08_smN). The official panel keeps them in ~/.config/TASCAM (press ⇧⌘G, then ⇧⌘. to show hidden folders)."
        p.canChooseFiles = true
        p.canChooseDirectories = false
        p.showsHiddenFiles = true
        p.directoryURL = officialFolder
        if p.runModal() == .OK, let url = p.url { model.importScene(file: url, into: slot) }
    }

    private func importFolder() {
        let p = NSOpenPanel()
        p.message = "Choose a folder containing US-16x08_sm1…10 files."
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.showsHiddenFiles = true
        p.directoryURL = officialFolder
        if p.runModal() == .OK, let url = p.url { model.importSceneFolder(url) }
    }

    private func exportAll() {
        let p = NSOpenPanel()
        p.message = "Choose a folder to write the scene files into."
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.canCreateDirectories = true
        p.prompt = "Export"
        if p.runModal() == .OK, let url = p.url { model.exportScenes(to: url) }
    }

    private func exportFile(_ slot: SceneSlot) {
        let p = NSSavePanel()
        p.nameFieldStringValue = OfficialScene.fileName(slot: slot.id)
        if p.runModal() == .OK, let url = p.url { model.exportScene(slot.id, to: url) }
    }
}
