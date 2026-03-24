// Gap 13: Image/asset loading — loads PNG/JPEG files to BitmapSurface via WIC

import CDirect2DInterop
import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK

@MainActor
public enum ImageLoader {
    public static func load(contentsOfFile path: String) -> BitmapSurface? {
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
        return BitmapSurface(width: width, height: height, bytesPerRow: bytesPerRow, pixels: data)
    }
}
