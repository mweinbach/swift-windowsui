import WinSDK

/// Face references borrowed by the bitmap drawing callback, retained only for
/// the synchronous raster attempt that owns this buffer. This is deliberately
/// not an actor: the C callback runs on the caller's drawing stack. The owner
/// resolves metadata after `Draw` returns and must not send this buffer to a
/// different thread.
///
/// The default V1 capture reads only faces. A separate, explicitly supplied V2
/// budget permits copying glyph indices for the fixed display-bitmap fixtures.
/// Text, layout positions, descriptions, and cache keys never enter here.
final class NativeBitmapFontDrawCapture {
    private let maxFaces: Int
    private let glyphBudget: NativeBitmapGlyphCaptureBudget?
    private let glyphRole: NativeBitmapFontRole?
    private var glyphRunsConsumed = false
    private(set) var faces: [NativeFontFaceHandle] = []
    private(set) var drawCount = 0
    private(set) var drawFailures = 0
    private(set) var truncated = false
    private(set) var glyphRuns: [NativeBitmapCapturedGlyphRun] = []
    private(set) var glyphsIncomplete = false

    init(
        maxFaces: Int = 8, glyphBudget: NativeBitmapGlyphCaptureBudget? = nil,
        glyphRole: NativeBitmapFontRole? = nil
    ) {
        self.maxFaces = min(8, max(0, maxFaces))
        self.glyphBudget = glyphBudget
        self.glyphRole = glyphRole
    }

    var capturesGlyphs: Bool { glyphBudget != nil }

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

    /// The renderer has already forwarded this exact borrowed run once. Copy
    /// its indices before the callback returns; do not retain borrowed arrays.
    /// This method is never entered by a V1 or candidate/sentinel capture.
    func recordGlyphRun(_ rawRun: UnsafeMutableRawPointer?, result: HRESULT) {
        guard let glyphBudget, glyphBudget.isOpen else { return }
        guard !glyphRunsConsumed else {
            glyphBudget.noteDropped()
            return
        }
        guard let rawRun else {
            recordDraw(fontFace: nil, result: result)
            glyphsIncomplete = true
            glyphBudget.noteDropped()
            return
        }
        let run = rawRun.assumingMemoryBound(to: DWRITE_GLYPH_RUN.self).pointee
        recordDraw(fontFace: run.fontFace, result: result)
        guard let rawFace = run.fontFace,
            let face = faces.first(where: { $0.rawPointer == rawFace }),
            run.glyphCount <= UInt32(NativeBitmapGlyphCaptureBudget.maximumGlyphsPerRun),
            run.glyphCount == 0 || run.glyphIndices != nil,
            drawCount <= NativeBitmapGlyphCaptureBudget.maximumRunsPerRaster
        else {
            glyphsIncomplete = true
            glyphBudget.noteDropped()
            return
        }
        let count = Int(run.glyphCount)
        guard glyphBudget.reserve(glyphCount: count) else {
            glyphsIncomplete = true
            return
        }
        let indices = Array(UnsafeBufferPointer(start: run.glyphIndices, count: count))
        glyphRuns.append(NativeBitmapCapturedGlyphRun(face: face, glyphIndices: indices, drawResult: result))
        if count == 0 || result < 0 { glyphsIncomplete = true }
    }

    /// Private raster-attempt binding. A capture from a different session,
    /// purpose, or role, or a replay of a completed capture, cannot contribute
    /// another draw observation or supply a bitmap receipt.
    func consumeGlyphRuns(for budget: NativeBitmapGlyphCaptureBudget, role: NativeBitmapFontRole) -> Bool {
        guard glyphBudget === budget, glyphRole == role, !glyphRunsConsumed else { return false }
        glyphRunsConsumed = true
        return true
    }
}

/// Owned by one V2 session and used only on its synchronous drawing stack.
/// Reservations happen before copying, so even rejected or unsealed attempts
/// cannot cause a session to copy more than the advertised limits.
final class NativeBitmapGlyphCaptureBudget {
    static let maximumGlyphsPerRun = 128
    static let maximumRunsPerRaster = 16
    static let maximumRuns = 256
    static let maximumGlyphs = 4_096

    private(set) var copiedRuns = 0
    private(set) var copiedGlyphs = 0
    private(set) var dropped = 0
    private(set) var isOpen = true

    func reserve(glyphCount: Int) -> Bool {
        guard isOpen, glyphCount >= 0, glyphCount <= Self.maximumGlyphsPerRun,
            copiedRuns < Self.maximumRuns, glyphCount <= Self.maximumGlyphs - copiedGlyphs
        else {
            noteDropped()
            return false
        }
        copiedRuns += 1
        copiedGlyphs += glyphCount
        return true
    }

    func noteDropped() {
        if dropped < Int.max { dropped += 1 }
    }

    func close() { isOpen = false }
}

struct NativeBitmapCapturedGlyphRun {
    let face: NativeFontFaceHandle
    let glyphIndices: [UInt16]
    let drawResult: HRESULT
}
