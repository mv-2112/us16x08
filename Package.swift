// swift-tools-version:5.9
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

import PackageDescription

let package = Package(
    name: "US16x08Panel",
    platforms: [.macOS("26.0")],   // Golden Gate (macOS 27) is the target; ToolbarSpacer needs macOS 26
    products: [
        .executable(name: "US16x08Panel", targets: ["US16x08Panel"]),
        .executable(name: "us16x08ctl", targets: ["us16x08ctl"]),
    ],
    targets: [
        // Thin C shim over IOKit's IOUSBDeviceInterface (the same mechanism the
        // original TASCAM app uses). Keeps COM-style vtable code out of Swift.
        .target(
            name: "CUSB",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        // Protocol, state model, transports. No UI. Fully unit-testable.
        .target(name: "US16x08Core", dependencies: ["CUSB"]),
        // SwiftUI app.
        .executableTarget(name: "US16x08Panel", dependencies: ["US16x08Core"]),
        // Command-line tool for hardware bring-up and the guided self-test.
        .executableTarget(name: "us16x08ctl", dependencies: ["US16x08Core"]),
        .testTarget(name: "US16x08CoreTests", dependencies: ["US16x08Core"]),
    ]
)
