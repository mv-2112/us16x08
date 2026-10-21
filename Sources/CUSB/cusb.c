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

#include "cusb.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct cusb_device {
    IOUSBDeviceInterface942 **dev;
    int is_open;
};

static const char *kDeviceClasses[] = {"IOUSBHostDevice", "IOUSBDevice"};

static int prop_int(io_service_t svc, CFStringRef key) {
    int value = -1;
    CFTypeRef ref = IORegistryEntryCreateCFProperty(svc, key, kCFAllocatorDefault, 0);
    if (ref) {
        if (CFGetTypeID(ref) == CFNumberGetTypeID()) {
            CFNumberGetValue((CFNumberRef)ref, kCFNumberIntType, &value);
        }
        CFRelease(ref);
    }
    return value;
}

static CFMutableDictionaryRef make_match(uint16_t vid, uint16_t pid, const char *cls) {
    CFMutableDictionaryRef match = IOServiceMatching(cls);
    if (!match) return NULL;
    int v = vid, p = pid;
    CFNumberRef nv = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &v);
    CFNumberRef np = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &p);
    CFDictionarySetValue(match, CFSTR(kUSBVendorID), nv);
    CFDictionarySetValue(match, CFSTR(kUSBProductID), np);
    CFRelease(nv);
    CFRelease(np);
    return match;
}

static io_service_t find_service(uint16_t vid, uint16_t pid) {
    for (int i = 0; i < 2; i++) {
        CFMutableDictionaryRef match = make_match(vid, pid, kDeviceClasses[i]);
        if (!match) continue;
        /* IOServiceGetMatchingService consumes `match`. */
        io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, match);
        if (svc) return svc;
    }
    return 0;
}

int cusb_list_text(char *buf, size_t size) {
    if (!buf || size == 0) return 0;
    buf[0] = 0;
    size_t used = 0;
    int count = 0;
    for (int c = 0; c < 2 && count == 0; c++) {
        CFMutableDictionaryRef match = IOServiceMatching(kDeviceClasses[c]);
        if (!match) continue;
        io_iterator_t it = 0;
        if (IOServiceGetMatchingServices(kIOMainPortDefault, match, &it) != KERN_SUCCESS) continue;
        io_service_t svc;
        while ((svc = IOIteratorNext(it)) != 0) {
            int vid = prop_int(svc, CFSTR("idVendor"));
            int pid = prop_int(svc, CFSTR("idProduct"));
            io_name_t name = "";
            IORegistryEntryGetName(svc, name);
            int n = snprintf(buf + used, size - used, "%04x:%04x  %s\n", vid, pid, name);
            if (n > 0 && (size_t)n < size - used) used += (size_t)n;
            count++;
            IOObjectRelease(svc);
        }
        IOObjectRelease(it);
    }
    return count;
}

int cusb_info_text(uint16_t vid, uint16_t pid, char *buf, size_t size) {
    if (!buf || size == 0) return -1;
    buf[0] = 0;
    io_service_t svc = find_service(vid, pid);
    if (!svc) return -1;
    static const char *keys[] = {"USB Product Name", "USB Vendor Name", "USB Serial Number",
                                 "bcdDevice", "Device Speed"};
    size_t used = 0;
    int count = 0;
    for (int i = 0; i < 5; i++) {
        CFStringRef key = CFStringCreateWithCString(kCFAllocatorDefault, keys[i], kCFStringEncodingUTF8);
        CFTypeRef ref = IORegistryEntryCreateCFProperty(svc, key, kCFAllocatorDefault, 0);
        CFRelease(key);
        if (!ref) continue;
        char value[256] = "";
        if (CFGetTypeID(ref) == CFStringGetTypeID()) {
            CFStringGetCString((CFStringRef)ref, value, sizeof(value), kCFStringEncodingUTF8);
        } else if (CFGetTypeID(ref) == CFNumberGetTypeID()) {
            int v = 0;
            CFNumberGetValue((CFNumberRef)ref, kCFNumberIntType, &v);
            snprintf(value, sizeof(value), "%d", v);
        }
        CFRelease(ref);
        int n = snprintf(buf + used, size - used, "%s=%s\n", keys[i], value);
        if (n > 0 && (size_t)n < size - used) {
            used += (size_t)n;
            count++;
        }
    }
    IOObjectRelease(svc);
    return count;
}

cusb_device *cusb_open(uint16_t vid, uint16_t pid, int *err) {
    io_service_t svc = find_service(vid, pid);
    if (!svc) {
        if (err) *err = CUSB_ERR_NOT_FOUND;
        return NULL;
    }
    IOCFPlugInInterface **plug = NULL;
    SInt32 score = 0;
    IOReturn kr = IOCreatePlugInInterfaceForService(svc, kIOUSBDeviceUserClientTypeID,
                                                    kIOCFPlugInInterfaceID, &plug, &score);
    IOObjectRelease(svc);
    if (kr != kIOReturnSuccess || !plug) {
        if (err) *err = kr ? kr : CUSB_ERR_NO_INTERFACE;
        return NULL;
    }
    IOUSBDeviceInterface942 **dev = NULL;
    HRESULT hr = (*plug)->QueryInterface(plug, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID942),
                                         (LPVOID *)&dev);
    (*plug)->Release(plug);
    if (hr || !dev) {
        if (err) *err = CUSB_ERR_NO_INTERFACE;
        return NULL;
    }
    cusb_device *d = (cusb_device *)calloc(1, sizeof(*d));
    if (!d) {
        (*dev)->Release(dev);
        if (err) *err = CUSB_ERR_NO_INTERFACE;
        return NULL;
    }
    d->dev = dev;
    return d;
}

void cusb_close(cusb_device *d) {
    if (!d) return;
    if (d->dev) {
        if (d->is_open) (*d->dev)->USBDeviceClose(d->dev);
        (*d->dev)->Release(d->dev);
    }
    free(d);
}

static IOReturn do_request(cusb_device *d, IOUSBDevRequest *r) {
    return (*d->dev)->DeviceRequest(d->dev, r);
}

int cusb_control(cusb_device *d, uint8_t request_type, uint8_t request, uint16_t value,
                 uint16_t index, void *data, uint16_t length, int *transferred) {
    if (!d || !d->dev) return CUSB_ERR_NO_INTERFACE;
    IOUSBDevRequest r;
    memset(&r, 0, sizeof(r));
    r.bmRequestType = request_type;
    r.bRequest = request;
    r.wValue = value;
    r.wIndex = index;
    r.wLength = length;
    r.pData = data;

    /* Endpoint-0 requests normally work without opening the device, which
     * avoids disturbing the system's audio driver. If the OS insists the
     * device be open, open it WITHOUT seizing and retry once. */
    IOReturn kr = do_request(d, &r);
    if (kr == kIOReturnNotOpen && !d->is_open) {
        if ((*d->dev)->USBDeviceOpen(d->dev) == kIOReturnSuccess) {
            d->is_open = 1;
            r.wLenDone = 0;
            kr = do_request(d, &r);
        }
    }
    if (transferred) *transferred = (int)r.wLenDone;
    return (int)kr;
}

struct cusb_watch {
    IONotificationPortRef port;
    io_iterator_t added;
    io_iterator_t removed;
    cusb_watch_cb cb;
    void *ctx;
};

static void watch_fire(cusb_watch *w, io_iterator_t it, int attached) {
    int n = 0;
    io_object_t o;
    while ((o = IOIteratorNext(it)) != 0) {
        IOObjectRelease(o);
        n++;
    }
    if (n > 0 && w->cb) w->cb(attached, w->ctx);
}
static void on_added(void *refcon, io_iterator_t it) { watch_fire((cusb_watch *)refcon, it, 1); }
static void on_removed(void *refcon, io_iterator_t it) { watch_fire((cusb_watch *)refcon, it, 0); }

static void watch_drain(io_iterator_t it) {
    io_object_t o;
    while ((o = IOIteratorNext(it)) != 0) IOObjectRelease(o);
}

void cusb_watch_stop(cusb_watch *w) {
    if (!w) return;
    if (w->added) IOObjectRelease(w->added);
    if (w->removed) IOObjectRelease(w->removed);
    if (w->port) IONotificationPortDestroy(w->port);
    free(w);
}

cusb_watch *cusb_watch_start(uint16_t vid, uint16_t pid, cusb_watch_cb cb, void *ctx) {
    cusb_watch *w = (cusb_watch *)calloc(1, sizeof(*w));
    if (!w) return NULL;
    w->cb = cb;
    w->ctx = ctx;
    w->port = IONotificationPortCreate(kIOMainPortDefault);
    if (!w->port) {
        free(w);
        return NULL;
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(w->port), kCFRunLoopDefaultMode);

    /* Each call consumes its matching dictionary, so build one per notification. */
    CFMutableDictionaryRef m1 = make_match(vid, pid, kDeviceClasses[0]);
    CFMutableDictionaryRef m2 = make_match(vid, pid, kDeviceClasses[0]);
    if (!m1 || !m2) {
        cusb_watch_stop(w);
        return NULL;
    }
    if (IOServiceAddMatchingNotification(w->port, kIOFirstMatchNotification, m1, on_added, w, &w->added) != KERN_SUCCESS ||
        IOServiceAddMatchingNotification(w->port, kIOTerminatedNotification, m2, on_removed, w, &w->removed) != KERN_SUCCESS) {
        cusb_watch_stop(w);
        return NULL;
    }
    /* Iterating once arms each notification; report nothing for devices already present. */
    watch_drain(w->added);
    watch_drain(w->removed);
    return w;
}

const char *cusb_strerror(int code) {
    if (code == 0) return "success";
    if (code == CUSB_ERR_NOT_FOUND) return "device not found (plugged in, powered, and the original panel quit?)";
    if (code == CUSB_ERR_NO_INTERFACE) return "could not obtain a USB device interface";
    switch ((unsigned int)code) {
    case 0xe00002c0u: return "no device (kIOReturnNoDevice)";
    case 0xe00002c1u: return "not privileged (kIOReturnNotPrivileged)";
    case 0xe00002c2u: return "bad argument (kIOReturnBadArgument)";
    case 0xe00002c5u: return "exclusive access: another client has the device open (kIOReturnExclusiveAccess)";
    case 0xe00002cdu: return "device not open (kIOReturnNotOpen)";
    case 0xe00002e2u: return "not permitted (kIOReturnNotPermitted)";
    case 0xe00002d5u: return "device busy (kIOReturnBusy)";
    case 0xe00002d6u: return "timed out (kIOReturnTimeout)";
    case 0xe00002d9u: return "device not attached (kIOReturnNotAttached)";
    case 0xe00002edu: return "device not responding (kIOReturnNotResponding): the unit stopped answering. Is another program (e.g. TASCAM's own panel) talking to it, or is the unit busy, asleep or being re-plugged?";
    case 0xe00002ebu: return "aborted (kIOReturnAborted)";
    case 0xe000404fu: return "pipe stalled: the device rejected the request (kIOUSBPipeStalled)";
    case 0xe0004051u: return "transaction timed out (kIOUSBTransactionTimeout)";
    default: return "unrecognised IOReturn";
    }
}
