// Gap 13: Image/asset loading -- loads WIC-supported files to BitmapSurface.

import CDirect2DInterop

import Foundation

import SwiftWindowsCore

import SwiftWindowsGraphics

import WinSDK

@MainActor
public enum ImageLoader {
    private static var cache: [String: BitmapSurface] = [:]

    public static func load(contentsOfFile path: String) -> BitmapSurface? {
        if let cached = cache[path] {
            return cached
        }

        var pixelsOut: UnsafeMutableRawPointer?
        var width: Int32 = 0
        var height: Int32 = 0
        var bytesPerRow: Int32 = 0

        let hr = path.withCString(encodedAs: UTF16.self) { widePath in
            SWU_LoadImageFileToBGRA(widePath, &pixelsOut, &width, &height, &bytesPerRow)
        }

        guard hr >= 0, let pixels = pixelsOut, width > 0, height > 0, bytesPerRow > 0 else {
            return nil
        }
        defer { SWU_FreeImagePixels(pixels) }

        let byteCount = Int(bytesPerRow * height)
        let data = Data(bytes: pixels, count: byteCount)
        // WIC converts to `GUID_WICPixelFormat32bppBGRA`, which is straight
        // (non-premultiplied) alpha — `32bppPBGRA` would be the other one.
        let surface = BitmapSurface(
            width: width, height: height, bytesPerRow: bytesPerRow, pixels: data, format: .bgra8Straight)
        cache[path] = surface
        return surface
    }
}
