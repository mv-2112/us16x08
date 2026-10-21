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

/// Credits, licence and the "unofficial" statement. Replaces the standard About panel.
struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        guard let v = info?["CFBundleShortVersionString"] as? String else { return "development build" }
        return "Version " + v
    }

    private func link(_ title: String, _ url: String) -> some View {
        Link(title, destination: URL(string: url)!).font(.caption)
    }

    /// Links for thanking the people whose work this builds on. None of the authors publishes a
    /// donation or wishlist page that we could find, so this is empty on purpose. Add entries as
    /// (title, url) pairs if one turns up.
    private let thanksLinks: [(String, String)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 76, height: 76)
                VStack(alignment: .leading, spacing: 2) {
                    Text("US-16x08 Panel").font(.title.bold())
                    Text("An unofficial control panel for the TASCAM US-16x08, native on Apple silicon.")
                        .foregroundStyle(.secondary)
                    Text(version).font(.caption).foregroundStyle(.secondary)
                }
            }

            GroupBox {
                Text("This is an independent, unofficial project. It is not made, endorsed, supported or approved by TASCAM or TEAC Corporation, by the Linux kernel or ALSA maintainers, or by the GNU Project, and is in no way affiliated with any of them. TASCAM and US-16x08 are trademarks of TEAC Corporation, used here only to say which hardware this works with.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(4)
            }

            section("Built with Claude",
                    "Claude, an AI assistant made by Anthropic, did much of the hard work: analysing the original panel and the Linux driver, working out how the unit talks over USB, and writing the code, tests and documentation.") {
                link("claude.ai", "https://claude.ai")
                link("Anthropic", "https://www.anthropic.com")
            }

            section("Based on GNU-licensed work by others",
                    "The USB protocol this program speaks comes from the Linux kernel's US-16x08 mixer driver. Detlef Urban wrote it after analysing the original software's USB traffic, and Takashi Iwai merged it into the kernel. Copyright © 2016 Detlef Urban, GPL-2.0-or-later. This program is a derivative work of it.") {
                link("Driver source (mixer_us16x08.c)", "https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/sound/usb/mixer_us16x08.c")
                link("Header (mixer_us16x08.h)", "https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/sound/usb/mixer_us16x08.h")
                link("The 2016 kernel commit", "https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=d2bb390a2081a36ffe906724d2848d846f2aeb29")
                link("Detlef's 2016 post on the linux-audio-dev list", "https://lists.linuxaudio.org/archives/linux-audio-dev/2016-August/036482.html")
            }

            section("Inspired by TASCAM's original",
                    "The layout and behaviour follow TASCAM's own US-16x08 Settings Panel. No TASCAM code or artwork is included; facts such as parameter ranges and EQ frequency steps were checked against the original panel and TASCAM's Reference Manual.") {
                link("TASCAM US-16x08", "https://tascam.com/us/product/us-16x08")
            }

            section("Licence",
                    "GNU General Public License, version 2 or (at your option) any later version. This program comes with no warranty. You may redistribute it and change it under the same terms; the source is part of what you receive.") {
                link("Read the GPL", "https://www.gnu.org/licenses/old-licenses/gpl-2.0.html")
            }

            if !thanksLinks.isEmpty {
                section("Say thanks", "If this is useful, these are good places to say so.") {
                    ForEach(0..<thanksLinks.count, id: \.self) { i in
                        link(thanksLinks[i].0, thanksLinks[i].1)
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 560)
    }

    private func section<Content: View>(_ title: String, _ text: String,
                                        @ViewBuilder links: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 2) { links() }
        }
    }
}
