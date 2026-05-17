import Foundation
import SwiftWindowsCore

// MARK: - Minimal PNG Writer (uncompressed DEFLATE blocks)

extension BitmapSurface {
    /// Writes the bitmap as a PNG file.
    /// Uses uncompressed DEFLATE blocks so no zlib dependency is required.
    /// File size is large but fully standard-compliant.
    public func writePNG(to url: URL) throws {
        let width = Int(self.width)
        let height = Int(self.height)
        let srcRowBytes = Int(bytesPerRow)
        let dstRowSize = 1 + width * 4  // filter byte + RGBA

        // Build raw scanline data: filter byte 0 + RGBA pixels per row
        var raw = [UInt8]()
        raw.reserveCapacity(height * dstRowSize)
        for y in 0..<height {
            raw.append(0)  // filter: None
            let srcRow = y * srcRowBytes
            for x in 0..<width {
                let src = srcRow + x * 4
                guard src + 3 < pixels.count else {
                    raw.append(contentsOf: [0, 0, 0, 0])
                    continue
                }
                // BGRA -> RGBA
                raw.append(pixels[src + 2])  // R
                raw.append(pixels[src + 1])  // G
                raw.append(pixels[src + 0])  // B
                raw.append(pixels[src + 3])  // A
            }
        }

        var idat = Data()
        idat.reserveCapacity(raw.count + 64)

        // zlib header: CM=8, CINFO=7, FLEVEL=0, FDICT=0 -> 0x78 0x01
        idat.append(contentsOf: [0x78, 0x01])

        // Uncompressed DEFLATE blocks
        let maxBlock = 65535
        var offset = 0
        while offset < raw.count {
            let remaining = raw.count - offset
            let chunk = min(remaining, maxBlock)
            let finalBlock = remaining <= maxBlock ? 1 : 0
            idat.append(UInt8(finalBlock))  // BFINAL=1, BTYPE=00
            idat.append(UInt8(chunk & 0xFF))
            idat.append(UInt8((chunk >> 8) & 0xFF))
            idat.append(UInt8((~chunk) & 0xFF))
            idat.append(UInt8((~chunk >> 8) & 0xFF))
            idat.append(contentsOf: raw[offset..<offset + chunk])
            offset += chunk
        }

        // adler32
        var s1: UInt32 = 1
        var s2: UInt32 = 0
        for byte in raw {
            s1 = (s1 + UInt32(byte)) % 65521
            s2 = (s2 + s1) % 65521
        }
        let adler = (s2 << 16) | s1
        idat.appendBigEndian(adler)

        var png = Data()
        png.reserveCapacity(8 + 25 + 12 + idat.count + 12 + 12)
        png.append(contentsOf: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        appendChunk(type: "IHDR", content: makeIHDR(width: width, height: height), to: &png)
        appendChunk(type: "IDAT", content: idat, to: &png)
        appendChunk(type: "IEND", content: Data(), to: &png)

        try png.write(to: url, options: .atomic)
    }
}

// MARK: - Private helpers

private func makeIHDR(width: Int, height: Int) -> Data {
    var d = Data()
    d.reserveCapacity(13)
    d.appendBigEndian(UInt32(width))
    d.appendBigEndian(UInt32(height))
    d.append(contentsOf: [8, 6, 0, 0, 0])  // 8-bit, RGBA, compression=0, filter=0, interlace=none
    return d
}

private func appendChunk(type: String, content: Data, to data: inout Data) {
    let typeBytes = Data(type.utf8)
    var crc: UInt32 = 0xFFFF_FFFF
    for b in typeBytes { crc = updateCRC(crc, byte: b) }
    for b in content { crc = updateCRC(crc, byte: b) }
    crc ^= 0xFFFF_FFFF

    data.appendBigEndian(UInt32(content.count))
    data.append(contentsOf: typeBytes)
    data.append(contentsOf: content)
    data.appendBigEndian(crc)
}

private let crcTable: [UInt32] = {
    var t = [UInt32](repeating: 0, count: 256)
    for n in 0..<256 {
        var c = UInt32(n)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
        }
        t[n] = c
    }
    return t
}()

private func updateCRC(_ crc: UInt32, byte: UInt8) -> UInt32 {
    crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
}

extension Data {
    fileprivate mutating func appendBigEndian(_ value: UInt32) {
        append(contentsOf: [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ])
    }
}
