import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK

final class NativeFontFaceHandle: @unchecked Sendable {
    private let rawValue: UInt
    let identifier: UInt64

    init?(_ rawPointer: UnsafeMutableRawPointer?) {
        guard let rawPointer else {
            return nil
        }

        let unknown = rawPointer.assumingMemoryBound(to: IUnknown.self)
        _ = unknown.pointee.lpVtbl.pointee.AddRef(unknown)

        self.rawValue = UInt(bitPattern: rawPointer)
        self.identifier = UInt64(UInt(bitPattern: rawPointer))
    }

    var rawPointer: UnsafeMutableRawPointer {
        UnsafeMutableRawPointer(bitPattern: rawValue)!
    }

    deinit {
        guard let rawPointer = UnsafeMutableRawPointer(bitPattern: rawValue) else {
            return
        }
        let unknown = rawPointer.assumingMemoryBound(to: IUnknown.self)
        _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
    }
}

struct NativeTextGlyphLayout: Sendable {
    var character: Character
    var origin: Point
    var advance: Double
    var glyphID: UInt32? = nil
    var fontFace: NativeFontFaceHandle? = nil
    var fontFamily: String = "Segoe UI"
    var weight: TextWeight = .regular
    var fontSize: Double = 0
    var sourceIndex: Int? = nil

    static func == (lhs: NativeTextGlyphLayout, rhs: NativeTextGlyphLayout) -> Bool {
        lhs.character == rhs.character
            && lhs.origin == rhs.origin
            && lhs.advance == rhs.advance
            && lhs.glyphID == rhs.glyphID
            && lhs.fontFace?.identifier == rhs.fontFace?.identifier
            && lhs.fontFamily == rhs.fontFamily
            && lhs.weight == rhs.weight
            && lhs.fontSize == rhs.fontSize
            && lhs.sourceIndex == rhs.sourceIndex
    }
}

extension NativeTextGlyphLayout: Equatable {}

struct NativeTextLineLayout: Equatable, Sendable {
    var text: String
    var width: Double
    var height: Double
    var ascent: Double = 0
    var descent: Double = 0
    var glyphs: [NativeTextGlyphLayout]
}

struct NativeTextLayoutResult: Equatable, Sendable {
    var lines: [NativeTextLineLayout]
    var lineSpacing: Double = 0
    var contentSize: Size
    var measuredSize: Size
}

struct NativeGlyphBitmap: Equatable, Sendable {
    var surface: BitmapSurface
    var bearingX: Float
    var bearingY: Float
    var advance: Float

    var width: Int32 { surface.width }
    var height: Int32 { surface.height }
    var pixels: Data { surface.pixels }
}
