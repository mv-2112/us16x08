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
import CUSB

public protocol US16x08Transport: AnyObject {
    /// Vendor OUT request 0x1D with the given payload.
    func send(_ message: [UInt8]) throws
    /// Vendor IN request 0x1E, reading `length` bytes (meter frames).
    func readMeterFrame(length: Int) throws -> [UInt8]
}

public enum TransportError: Error, CustomStringConvertible {
    case open(code: Int32)
    case transfer(code: Int32, what: String)

    public var description: String {
        switch self {
        case .open(let c):
            return "Could not open US-16x08: \(String(cString: cusb_strerror(c))) [\(String(format: "0x%08x", UInt32(bitPattern: c)))]"
        case .transfer(let c, let what):
            return "USB \(what) failed: \(String(cString: cusb_strerror(c))) [\(String(format: "0x%08x", UInt32(bitPattern: c)))]"
        }
    }
}

public final class USBTransport: US16x08Transport {
    private var handle: OpaquePointer?

    public init(vendorID: UInt16 = US16x08.vendorID, productID: UInt16 = US16x08.productID) throws {
        var err: Int32 = 0
        guard let h = cusb_open(vendorID, productID, &err) else { throw TransportError.open(code: err) }
        handle = h
    }

    deinit { if let h = handle { cusb_close(h) } }

    /// Errors worth retrying: not responding, busy, timeout, USB transaction timeout, pipe stall.
    private static let retryable: Set<UInt32> = [0xe00002ed, 0xe00002d5, 0xe00002d6, 0xe0004051, 0xe000404f]

    /// The original panel retries failed transfers a few times 5 ms apart; so do we.
    private func attempt(_ what: String, _ body: () -> Int32) throws {
        var r: Int32 = 0
        for n in 0..<5 {
            r = body()
            if r == 0 { return }
            if !USBTransport.retryable.contains(UInt32(bitPattern: r)) || n == 4 { break }
            Thread.sleep(forTimeInterval: 0.005)
        }
        throw TransportError.transfer(code: r, what: what)
    }

    public func send(_ message: [UInt8]) throws {
        var buf = message
        var done: Int32 = 0
        let count = UInt16(message.count)
        try attempt("send") {
            buf.withUnsafeMutableBytes { raw in
                cusb_control(handle, US16x08.Request.setType, US16x08.Request.set, 0, 0, raw.baseAddress, count, &done)
            }
        }
    }

    public func readMeterFrame(length: Int) throws -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: length)
        var done: Int32 = 0
        let count = UInt16(length)
        try attempt("meter read") {
            buf.withUnsafeMutableBytes { raw in
                cusb_control(handle, US16x08.Request.metersType, US16x08.Request.meters, 0, 0, raw.baseAddress, count, &done)
            }
        }
        return buf
    }

    /// Text listing of every USB device the Mac can see (for troubleshooting).
    public static func listDevices() -> String {
        let size = 16384
        var buf = [CChar](repeating: 0, count: size)
        _ = cusb_list_text(&buf, size)
        return String(cString: buf)
    }
}

/// Prints instead of sending. Lets the CLI and tests run without hardware.
public final class DryRunTransport: US16x08Transport {
    public private(set) var sent: [[UInt8]] = []
    public var printToStdout = true
    public init() {}
    public func send(_ message: [UInt8]) throws {
        sent.append(message)
        if printToStdout { print("[dry-run] OUT 0x1D  \(hexString(message))") }
    }
    public func readMeterFrame(length: Int) throws -> [UInt8] {
        if printToStdout { print("[dry-run] IN  0x1E  (\(length) bytes) -> zeros") }
        return [UInt8](repeating: 0, count: length)
    }
}
