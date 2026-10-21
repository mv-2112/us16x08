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

/// Mirrors the original panel's Interface page (Software Version, Firmware Version, Device,
/// Sample Rate, Mixer True Bypass) with extra unit details underneath.
struct InterfaceScreen: View {
    @EnvironmentObject var model: AppModel

    /// Same shape as the original ("2.10 0048"): version, then build padded to 4 digits.
    private var panelVersion: String {
        let info = Bundle.main.infoDictionary
        guard let v = info?["CFBundleShortVersionString"] as? String else { return "development build" }
        let build = Int((info?["CFBundleVersion"] as? String) ?? "") ?? 0
        return v + " " + String(format: "%04d", build)
    }

    private var buildStamp: String {
        let parts = [model.firmware?.buildDate, model.firmware?.buildTime].compactMap { $0 }
        return parts.isEmpty ? "—" : parts.joined(separator: " ")
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Software Version") { Text(panelVersion) }
                LabeledContent("Firmware Version") {
                    if let text = model.firmware?.displayText {
                        Text(text)
                    } else {
                        Text(model.connected ? "Not reported" : "Connect to read").foregroundStyle(.secondary)
                    }
                }
                .help("Read from the unit with the same query the original panel uses.")
                LabeledContent("Device") {
                    Text(model.firmware?.productName ?? model.info.productName ?? "—")
                }
                LabeledContent("Sample Rate") { Text(model.info.sampleRateText ?? "—") }
                LabeledContent("Mixer True Bypass") {
                    Picker("Mixer True Bypass",
                           selection: Binding(get: { model.state.bypass }, set: { model.setBypass($0) })) {
                        Text("ON").tag(true)
                        Text("OFF").tag(false)
                    }
                    .pickerStyle(.radioGroup)
                    .horizontalRadioGroupLayout()
                    .labelsHidden()
                    .disabled(!model.connected)
                }
                .help(model.connected
                      ? "Input and output matched binary while the mixer's signal processing is bypassed (v2.10)."
                      : "Connect the unit to change Mixer True Bypass.")
            }
            Section("Unit details") {
                LabeledContent("Firmware build") { Text(buildStamp) }
                LabeledContent("Manufacturer") { Text(model.info.vendorName ?? "—") }
                LabeledContent("Serial number") { Text(model.info.serial ?? "—") }
                LabeledContent("USB speed") { Text(model.info.usbSpeed ?? "—") }
                LabeledContent("Core Audio device") { Text(model.info.audioDeviceName ?? "—") }
                Button("Refresh") {
                    model.refreshInfo()
                    model.refreshFirmware()
                }
                Button("Open Audio MIDI Setup") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app"))
                }
                .help("The sample rate is set there or in your DAW, not in this panel.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            model.refreshInfo()
            model.refreshFirmware()
        }
    }
}
