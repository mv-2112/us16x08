#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# US-16x08 Panel: an unofficial control panel for the TASCAM US-16x08.
# Not affiliated with TASCAM / TEAC Corporation, the Linux kernel or ALSA
# maintainers, or the GNU Project.
#
# Derivative work. The USB protocol knowledge used here comes from the Linux
# kernel driver sound/usb/mixer_us16x08.c, Copyright (c) 2016 by Detlef Urban,
# GPL-2.0-or-later.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version. It is distributed WITHOUT ANY WARRANTY. See the file COPYING.

# Builds a native Apple Silicon (arm64) .app bundle with an ad-hoc signature.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --product US16x08Panel
BIN="$(swift build -c release --arch arm64 --show-bin-path)/US16x08Panel"

APP="build/US16x08 Panel.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/US16x08Panel"
# GPL: the licence text and notice travel with every copy of the app.
cp COPYING NOTICE.md Resources/AppIcon.icns "$APP/Contents/Resources/"
if ! grep -q "GNU GENERAL PUBLIC LICENSE" COPYING; then
  echo "WARNING: COPYING is only a stub. Run Scripts/fetch_license.sh before distributing this app." >&2
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>US-16x08 Panel</string>
  <key>CFBundleDisplayName</key><string>US-16x08 Panel (unofficial)</string>
  <key>CFBundleIdentifier</key><string>local.unofficial.us16x08panel</string>
  <key>CFBundleExecutable</key><string>US16x08Panel</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>GPL-2.0-or-later. Unofficial; not affiliated with TASCAM. See NOTICE.md.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo
echo "Built: $APP"
echo -n "Architectures: "; lipo -archs "$APP/Contents/MacOS/US16x08Panel"
