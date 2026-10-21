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

public struct SceneSlot: Codable, Equatable, Identifiable {
    public var id: Int
    public var name: String
    public var state: MixerState?
    public var savedAt: Date?
    public init(id: Int) {
        self.id = id
        self.name = "Scene \(id + 1)"
    }
}

/// Scenes are kept in TASCAM's own file format (see `OfficialScene`): a folder holding `US-16x08_sm1.ini` … `sm10.ini`
/// plus `US-16x08_SceneMemory.ini` for the names. Copy files in either direction to share scenes with the official panel.
public enum SceneStore {
    public static let slotCount = 10

    public static var folderURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("US16x08Panel", isDirectory: true).appendingPathComponent("Scenes", isDirectory: true)
    }
    /// Scenes saved by earlier builds (JSON); migrated once.
    static var legacyURL: URL { folderURL.deletingLastPathComponent().appendingPathComponent("scenes.json") }

    public static func load() -> [SceneSlot] {
        let fm = FileManager.default
        if !fm.fileExists(atPath: folderURL.path), let data = try? Data(contentsOf: legacyURL),
           let old = try? JSONDecoder().decode([SceneSlot].self, from: data) {
            var slots = (0..<slotCount).map { SceneSlot(id: $0) }
            for s in old where s.id >= 0 && s.id < slotCount { slots[s.id] = s }
            write(slots, to: folderURL)
            try? fm.moveItem(at: legacyURL, to: legacyURL.appendingPathExtension("migrated"))
            return slots
        }
        return read(from: folderURL)
    }

    public static func save(_ slots: [SceneSlot]) { write(slots, to: folderURL) }

    // MARK: Folders (ours, or a copy of the official panel's)

    /// Finds `US-16x08_smN` in `dir` whatever its extension, and the names file.
    public static func read(from dir: URL) -> [SceneSlot] {
        var slots = (0..<slotCount).map { SceneSlot(id: $0) }
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var names: [Int: String] = [:]
        if let nf = files.first(where: { $0.lastPathComponent.hasPrefix("US-16x08_SceneMemory") }),
           let text = try? String(contentsOf: nf, encoding: .utf8) {
            names = OfficialScene.names(from: INIDocument(text: text))
        }
        for i in 0..<slotCount {
            let stem = "US-16x08_sm\(i + 1)"
            if let f = files.first(where: { $0.deletingPathExtension().lastPathComponent == stem || $0.lastPathComponent == stem }),
               let text = try? String(contentsOf: f, encoding: .utf8) {
                let (state, report) = OfficialScene.state(from: INIDocument(text: text))
                if report.applied > 0 {
                    slots[i].state = state
                    slots[i].savedAt = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                }
            }
            if let n = names[i] { slots[i].name = n }
        }
        return slots
    }

    public static func write(_ slots: [SceneSlot], to dir: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for s in slots where s.id >= 0 && s.id < slotCount {
            let url = dir.appendingPathComponent(OfficialScene.fileName(slot: s.id))
            if let st = s.state {
                try? OfficialScene.document(from: st).text().write(to: url, atomically: true, encoding: .utf8)
            } else {
                try? fm.removeItem(at: url)
            }
        }
        let names = (0..<slotCount).map { i in slots.first(where: { $0.id == i })?.name ?? "Scene \(i + 1)" }
        try? OfficialScene.namesDocument(names).text()
            .write(to: dir.appendingPathComponent(OfficialScene.namesFileName), atomically: true, encoding: .utf8)
    }
}
