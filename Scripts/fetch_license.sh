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

# Installs the full GNU GPL v2 text as COPYING. Run once before distributing the app.
set -euo pipefail
cd "$(dirname "$0")/.."
curl -fsSL https://www.gnu.org/licenses/old-licenses/gpl-2.0.txt -o COPYING
echo "Wrote COPYING ($(wc -l < COPYING | tr -d ' ') lines)"
