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
import US16x08Core

struct MixerScreen: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            DSPPanel(index: model.selectedChannel)
            GeometryReader { geo in
                let count = CGFloat(US16x08.channelCount)
                let gaps = Layout.stripGap * (count - 1)
                let avail = geo.size.width - 2 * Layout.outerPad - Layout.masterWidth - Layout.masterGap - gaps - Layout.stripGap
                let w = min(max(avail / count, Layout.stripMin), Layout.stripMax)
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: Layout.stripGap) {
                            InputGroupLabel(text: "MIC 1–8", count: 8, stripWidth: w,
                                            help: "XLR microphone inputs on the front panel. Gain is set with the knobs on the unit.")
                            InputGroupLabel(text: "LINE / INST 9–10", count: 2, stripWidth: w,
                                            help: "Front-panel jack inputs, switchable between line and instrument on the unit.")
                            InputGroupLabel(text: "LINE 11–16", count: 6, stripWidth: w,
                                            help: "Line inputs on the back of the unit.")
                            Text("MASTER")
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                                .frame(width: Layout.masterWidth, height: Layout.captionHeight)
                                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                                .padding(.leading, Layout.masterGap - Layout.stripGap)
                        }
                        HStack(alignment: .top, spacing: Layout.stripGap) {
                            ForEach(0..<US16x08.channelCount, id: \.self) { ChannelStrip(index: $0).frame(width: w) }
                            MasterStrip().frame(width: Layout.masterWidth)
                                .padding(.leading, Layout.masterGap - Layout.stripGap)
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .padding(Layout.outerPad)
                    .frame(minWidth: geo.size.width, alignment: .leading)
                }
            }
        }
    }
}

struct InputGroupLabel: View {
    let text: String
    let count: Int
    let stripWidth: CGFloat
    let help: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: CGFloat(count) * stripWidth + CGFloat(count - 1) * Layout.stripGap, height: Layout.captionHeight)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .help(help)
    }
}

/// Shared look for a strip (channel or master) so the two always line up.
private struct StripBackground: ViewModifier {
    var selected = false
    func body(content: Content) -> some View {
        content
            .padding(5)
            .frame(maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 2 : 1)
            )
    }
}

struct ChannelStrip: View {
    @EnvironmentObject var model: AppModel
    let index: Int

    var body: some View {
        let ch = model.state.channels[index]
        let selected = model.selectedChannel == index
        let bypass = model.state.bypass
        VStack(spacing: 4) {
            Text("\(index + 1)").font(.caption.weight(.semibold)).frame(height: 14)
            VStack(spacing: Layout.chipSpacing) {
                ChipToggle(title: "PHASE", isOn: ch.phase, tint: .purple, help: "Invert polarity") { model.setPhase(index, $0) }
                    .disabled(bypass)
                ChipToggle(title: "EQ", isOn: ch.eqEnabled, tint: .blue) { model.setEQEnabled(index, $0) }
                    .disabled(bypass)
                ChipToggle(title: "COMP", isOn: ch.comp.enabled, tint: .orange) { v in model.updateComp(index) { $0.enabled = v } }
                    .disabled(bypass)
                ChipToggle(title: "SOLO", isOn: false, tint: .yellow, help: "Solo isn't supported yet (protocol not captured)") { _ in }
                    .disabled(true)
                ChipToggle(title: "MUTE", isOn: ch.mute, tint: .red) { model.setMute(index, $0) }
            }
            PanKnob(pos: ch.pan) { model.setPan(index, $0) }
            HStack(spacing: 3) {
                Fader(db: ch.faderDB) { model.setFader(index, $0) }
                    .frame(width: 26)
                LiveMeter(store: model.meterStore, source: .input(index), active: model.metersOn)
                    .frame(width: 9)
            }
            .frame(minHeight: Layout.faderMin, maxHeight: .infinity)
            Text(faderLabel(ch.faderDB))
                .font(.system(size: 10)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                .frame(height: 14)
            ChipToggle(title: "LINK", isOn: false, help: "Stereo link isn't supported yet (protocol not captured)") { _ in }
                .disabled(true)
        }
        .modifier(StripBackground(selected: selected))
        .contentShape(Rectangle())
        .onTapGesture { model.selectedChannel = index }
    }
}

/// Same rows as a channel, so every control lines up with the channels beside it.
struct MasterStrip: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 4) {
            Text("L/R").font(.caption.weight(.semibold)).frame(height: 14)
            VStack(spacing: Layout.chipSpacing) {
                Color.clear.frame(height: Layout.chipHeight)                    // PHASE row
                ChipToggle(title: "BYPASS", isOn: model.state.bypass, tint: .teal,
                           help: model.connected ? "Mixer True Bypass: input and output matched binary, mixer processing skipped"
                                                 : "Connect the unit to change Mixer True Bypass") { model.setBypass($0) }
                    .disabled(!model.connected)                                 // EQ row
                Color.clear.frame(height: Layout.chipHeight)                    // COMP row
                Color.clear.frame(height: Layout.chipHeight)                    // SOLO row
                ChipToggle(title: "MUTE", isOn: model.state.masterMute, tint: .red) { model.setMasterMute($0) }
            }
            Color.clear.frame(height: Layout.panHeight)                         // pan row
            HStack(spacing: 3) {
                Fader(db: model.state.masterFaderDB) { model.setMasterFader($0) }
                    .frame(width: 26)
                ForEach(0..<2, id: \.self) { side in
                    LiveMeter(store: model.meterStore, source: .master(side), active: model.metersOn)
                        .frame(width: 8)
                }
            }
            .frame(minHeight: Layout.faderMin, maxHeight: .infinity)
            Text(faderLabel(model.state.masterFaderDB))
                .font(.system(size: 10)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                .frame(height: 14)
            ChipToggle(title: "PEAKS", isOn: false, tint: .gray, help: "Clear all peak-hold segments and clip LEDs") { _ in model.clearPeaks() }
        }
        .modifier(StripBackground())
    }
}
