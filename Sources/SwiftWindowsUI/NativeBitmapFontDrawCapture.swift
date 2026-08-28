import WinSDK

/// Face references borrowed by the bitmap drawing callback, retained only for
/// the synchronous raster attempt that owns this buffer. This is deliberately
/// not an actor: the C callback runs on the caller's drawing stack. The owner
/// resolves metadata after `Draw` returns and must not send this buffer to a
/// different thread.
///
/// Counts describe callback outcomes internally, never glyph counts or exported
/// content. No glyph arrays, text, layout positions, or cache keys enter here.
final class NativeBitmapFontDrawCapture {
    private let maxFaces: Int
    private(set) var faces: [NativeFontFaceHandle] = []
    private(set) var drawCount = 0
    private(set) var drawFailures = 0
    private(set) var truncated = false

    init(maxFaces: Int = 8) {
        self.maxFaces = min(8, max(0, maxFaces))
    }

    /// Retain each distinct borrowed face pointer once. The run still owns its
    /// reference; only the additional reference held by `faces` is released
    /// when this capture is destroyed. A missing face also makes attribution
    /// incomplete, even when the underlying draw returned success.
    func recordDraw(fontFace: UnsafeMutableRawPointer?, result: HRESULT) {
        if drawCount < Int.max {
            drawCount += 1
        }
        if result < 0, drawFailures < Int.max {
            drawFailures += 1
        }
        guard let fontFace else {
            truncated = true
            return
        }
        guard !faces.contains(where: { $0.rawPointer == fontFace }) else {
            return
        }
        guard faces.count < maxFaces, let face = NativeFontFaceHandle(fontFace) else {
            truncated = true
            return
        }
        faces.append(face)
    }
}
