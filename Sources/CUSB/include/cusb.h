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

#ifndef CUSB_H
#define CUSB_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Error code used when no matching device is present (not an IOReturn).
#define CUSB_ERR_NOT_FOUND (-1)
#define CUSB_ERR_NO_INTERFACE (-2)

typedef struct cusb_device cusb_device;

/// Writes "vvvv:pppp  Name\n" for every USB device into buf. Returns the count.
int cusb_list_text(char *buf, size_t size);

/// Reads a few IORegistry properties of the first matching device as "key=value\n" lines
/// (USB Product Name, USB Vendor Name, USB Serial Number, bcdDevice, Device Speed).
/// Returns the number of properties found, or -1 if no matching device is present.
int cusb_info_text(uint16_t vid, uint16_t pid, char *buf, size_t size);

/// Opens the first device matching vid/pid. On failure returns NULL and stores
/// an IOReturn (or CUSB_ERR_*) in *err.
cusb_device *cusb_open(uint16_t vid, uint16_t pid, int *err);
void cusb_close(cusb_device *dev);

/// Control transfer on endpoint 0. For IN transfers (bit 7 of request_type
/// set) `data` receives up to `length` bytes. Returns an IOReturn (0 = success).
int cusb_control(cusb_device *dev, uint8_t request_type, uint8_t request,
                 uint16_t value, uint16_t index, void *data, uint16_t length,
                 int *transferred);

/// Hot-plug watcher. `cb(1, ctx)` fires when a matching device appears, `cb(0, ctx)` when it
/// disappears. Callbacks run on the main run loop. Devices already present at start are not reported.
typedef struct cusb_watch cusb_watch;
typedef void (*cusb_watch_cb)(int attached, void *ctx);
cusb_watch *cusb_watch_start(uint16_t vid, uint16_t pid, cusb_watch_cb cb, void *ctx);
void cusb_watch_stop(cusb_watch *w);

const char *cusb_strerror(int code);

#ifdef __cplusplus
}
#endif

#endif
