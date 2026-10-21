#!/usr/bin/env python3
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

"""Literal port of the message-building logic in the Linux kernel's
sound/usb/mixer_us16x08.c (GPL-2.0-or-later, (c) 2016 Detlef Urban).
Used ONLY to generate golden test vectors for the Swift implementation, so the
Swift code is checked against an independent transcription of the driver."""

route_msg = [0x61,0x02,0x03,0x62,0x02,0x01,0x41,0x01,0x61,0x02,0x01,0x62,0x02,0x01,0x42,0x01,0x43,0x01,0x00,0x00]
mix_msg_in  = [0x61,0x02,0x04,0x62,0x02,0x01,0x81,0x02,0x00,0x00,0x00]
mix_msg_out = [0x61,0x02,0x02,0x62,0x02,0x01,0x81,0x02,0x00,0x00,0x00]
bypass_msg_out = [0x45,0x02,0x01,0x00,0x00]
bus_msg_out    = [0x44,0x02,0x01,0x00,0x00]
comp_msg = [0x61,0x02,0x04,0x62,0x02,0x01, 0x91,0x02,0xf0, 0x92,0x02,0x0a, 0x93,0x02,0x02,
            0x94,0x02,0x01, 0x95,0x02,0x03, 0x96,0x02,0x01, 0x97,0x02,0x01, 0x00,0x00]
eqs_msq = [0x61,0x02,0x04,0x62,0x02,0x01, 0x51,0x02,0x04, 0x52,0x02,0x0c, 0x53,0x02,0x0f,
           0x54,0x02,0x02, 0x55,0x02,0x01, 0x00,0x00]
ratio_map = [0x0a,0x0b,0x0d,0x0f,0x11,0x14,0x19,0x1e,0x23,0x28,0x32,0x3c,0x50,0xa0,0xff]
b = lambda v: v & 0xff

def channel_put(index, ctl_id, alsa_val, bias):      # snd_us16x08_channel_put
    buf = list(mix_msg_in); buf[8] = b(alsa_val - bias); buf[6] = ctl_id; buf[5] = index + 1; return buf
def master_put(alsa_val):                              # snd_us16x08_master_put (index 0)
    buf = list(mix_msg_out); buf[8] = b(alsa_val - 127); buf[6] = 0x81; buf[5] = 1; return buf
def master_mute(v):                                    # bus_put, ID_MUTE
    buf = list(mix_msg_out); buf[8] = v; buf[6] = 0x83; buf[5] = 1; return buf
def bypass(v): buf = list(bypass_msg_out); buf[2] = v; return buf
def bus(v):    buf = list(bus_msg_out);    buf[2] = v; return buf
def route(output, val):                                # snd_us16x08_route_put
    buf = list(route_msg)
    if val < 2: buf[2] = 0x02; org = val
    else:       buf[2] = 0x03; org = val - 2
    buf[5] = (org & 0x0f) + 1; buf[13] = output + 1; return buf
def comp(index, thr_alsa, ratio, attack_alsa, release_alsa, gain, sw):   # comp_put
    buf = list(comp_msg)
    buf[8] = b(thr_alsa - 0x20); buf[11] = ratio_map[ratio]; buf[14] = attack_alsa + 2
    buf[17] = release_alsa + 1; buf[20] = gain; buf[26] = sw; buf[5] = index + 1; return buf
def eq(index, band, gain, freq, width, sw):            # eq_put (raw values, no bias)
    buf = list(eqs_msq); buf[20] = sw; buf[17] = width; buf[14] = freq; buf[11] = gain
    buf[5] = index + 1; buf[8] = band + 1; return buf

H = lambda m: " ".join("%02x" % x for x in m)
V = [
 ("faderUnity",        channel_put(0, 0x81, 127, 127)),
 ("faderMinusInf",     channel_put(15, 0x81, 0, 127)),
 ("faderPlus6",        channel_put(2, 0x81, 133, 127)),
 ("faderMinus10",      channel_put(4, 0x81, 117, 127)),
 ("panCenter",         channel_put(1, 0x82, 127, 127)),
 ("panFullRight",      channel_put(1, 0x82, 254, 127)),
 ("panFullLeft",       channel_put(1, 0x82, 0, 127)),
 ("muteOn",            channel_put(3, 0x83, 1, 0)),
 ("phaseOn",           channel_put(0, 0x85, 1, 0)),
 ("masterFaderMinus10",master_put(117)),
 ("masterMuteOn",      master_mute(1)),
 ("bypassOn",          bypass(1)),
 ("bussOutOff",        bus(0)),
 ("routeOut1MasterR",  route(0, 1)),
 ("routeOut8Comp8",    route(7, 9)),
 ("routeOut3Comp3",    route(2, 4)),
 ("compDefaults",      comp(0, 0x20, 0, 0, 0, 0, 0)),
 ("compCustom",        comp(5, 12, 14, 98, 49, 10, 1)),
 ("eqLowDefaults",     eq(0, 0, 0x0c, 0x05, 0xff, 0)),
 ("eqHighMidCustom",   eq(3, 2, 20, 0x1b, 4, 1)),
 ("eqHighKernelRaw",   eq(0, 3, 0x0c, 0x0f, 0xff, 1)),
]
if __name__ == "__main__":
    for n, m in V: print('%-20s "%s"' % (n, H(m)))
    print("meterInit1 ", H([0x71,0x01,0x00,0x00]))
