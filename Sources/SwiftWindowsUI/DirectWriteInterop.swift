import WinSDK

typealias DWriteFactoryType = UINT32
typealias DWriteFontWeight = UINT32
typealias DWriteFontStyle = UINT32
typealias DWriteFontStretch = UINT32
typealias DWriteTextAlignment = UINT32
typealias DWriteParagraphAlignment = UINT32
typealias DWriteWordWrapping = UINT32
typealias DWriteRenderingMode = UINT32
typealias DWritePixelGeometry = UINT32
typealias DWriteMeasuringMode = UINT32
typealias DWriteReadingDirection = UINT32
typealias DWriteFlowDirection = UINT32
typealias DWriteLineSpacingMethod = UINT32

let dwriteFactoryTypeShared: DWriteFactoryType = 0
let dwriteFontStyleNormal: DWriteFontStyle = 0
let dwriteFontStretchNormal: DWriteFontStretch = 5
let dwriteTextAlignmentLeading: DWriteTextAlignment = 0
let dwriteTextAlignmentTrailing: DWriteTextAlignment = 1
let dwriteTextAlignmentCenter: DWriteTextAlignment = 2
let dwriteParagraphAlignmentNear: DWriteParagraphAlignment = 0
let dwriteParagraphAlignmentFar: DWriteParagraphAlignment = 1
let dwriteParagraphAlignmentCenter: DWriteParagraphAlignment = 2
let dwriteWordWrappingWrap: DWriteWordWrapping = 0
let dwriteWordWrappingNoWrap: DWriteWordWrapping = 1
let dwritePixelGeometryFlat: DWritePixelGeometry = 0
let dwriteRenderingModeNatural: DWriteRenderingMode = 4
let dwriteMeasuringModeNatural: DWriteMeasuringMode = 0
let dwriteReadingDirectionLeftToRight: DWriteReadingDirection = 0
let dwriteFlowDirectionTopToBottom: DWriteFlowDirection = 0
let dwriteLineSpacingMethodDefault: DWriteLineSpacingMethod = 0
let dwriteLineSpacingMethodProportional: DWriteLineSpacingMethod = 2

struct DWRITE_TEXT_RANGE {
    var startPosition: UINT32 = 0
    var length: UINT32 = 0
}

struct DWRITE_MATRIX {
    var m11: FLOAT = 1
    var m12: FLOAT = 0
    var m21: FLOAT = 0
    var m22: FLOAT = 1
    var dx: FLOAT = 0
    var dy: FLOAT = 0
}

struct DWRITE_GLYPH_OFFSET {
    var advanceOffset: FLOAT = 0
    var ascenderOffset: FLOAT = 0
}

struct DWRITE_GLYPH_RUN {
    var fontFace: UnsafeMutableRawPointer?
    var fontEmSize: FLOAT = 0
    var glyphCount: UINT32 = 0
    var glyphIndices: UnsafePointer<UINT16>?
    var glyphAdvances: UnsafePointer<FLOAT>?
    var glyphOffsets: UnsafePointer<DWRITE_GLYPH_OFFSET>?
    var isSideways: WindowsBool = WindowsBool(false)
    var bidiLevel: UINT32 = 0
}

struct DWRITE_GLYPH_RUN_DESCRIPTION {
    var localeName: UnsafePointer<WCHAR>?
    var string: UnsafePointer<WCHAR>?
    var stringLength: UINT32 = 0
    var clusterMap: UnsafePointer<UINT16>?
    var textPosition: UINT32 = 0
}

struct DWRITE_UNDERLINE {
    var width: FLOAT = 0
    var thickness: FLOAT = 0
    var offset: FLOAT = 0
    var runHeight: FLOAT = 0
    var readingDirection: DWriteReadingDirection = dwriteReadingDirectionLeftToRight
    var flowDirection: DWriteFlowDirection = dwriteFlowDirectionTopToBottom
    var localeName: UnsafePointer<WCHAR>?
    var measuringMode: DWriteMeasuringMode = dwriteMeasuringModeNatural
}

struct DWRITE_STRIKETHROUGH {
    var width: FLOAT = 0
    var thickness: FLOAT = 0
    var offset: FLOAT = 0
    var readingDirection: DWriteReadingDirection = dwriteReadingDirectionLeftToRight
    var flowDirection: DWriteFlowDirection = dwriteFlowDirectionTopToBottom
    var localeName: UnsafePointer<WCHAR>?
    var measuringMode: DWriteMeasuringMode = dwriteMeasuringModeNatural
}

struct DWRITE_TEXT_METRICS {
    var left: FLOAT = 0
    var top: FLOAT = 0
    var width: FLOAT = 0
    var widthIncludingTrailingWhitespace: FLOAT = 0
    var height: FLOAT = 0
    var layoutWidth: FLOAT = 0
    var layoutHeight: FLOAT = 0
    var maxBidiReorderingDepth: UINT32 = 0
    var lineCount: UINT32 = 0
}

struct DWRITE_OVERHANG_METRICS {
    var left: FLOAT = 0
    var top: FLOAT = 0
    var right: FLOAT = 0
    var bottom: FLOAT = 0
}

struct DWRITE_HIT_TEST_METRICS {
    var textPosition: UINT32 = 0
    var length: UINT32 = 0
    var left: FLOAT = 0
    var top: FLOAT = 0
    var width: FLOAT = 0
    var height: FLOAT = 0
    var bidiLevel: UINT32 = 0
    var isText: WindowsBool = WindowsBool(false)
    var isTrimmed: WindowsBool = WindowsBool(false)
}

struct IDWriteFactory { var lpVtbl: UnsafeMutablePointer<IDWriteFactoryVtbl>? }
struct IDWriteTextFormat { var lpVtbl: UnsafeMutablePointer<IDWriteTextFormatVtbl>? }
struct IDWriteTextLayout { var lpVtbl: UnsafeMutablePointer<IDWriteTextLayoutVtbl>? }
struct IDWriteGdiInterop { var lpVtbl: UnsafeMutablePointer<IDWriteGdiInteropVtbl>? }
struct IDWriteBitmapRenderTarget { var lpVtbl: UnsafeMutablePointer<IDWriteBitmapRenderTargetVtbl>? }
struct IDWriteRenderingParams { var lpVtbl: UnsafeMutablePointer<IDWriteRenderingParamsVtbl>? }
struct IDWriteTextRenderer { var lpVtbl: UnsafeMutablePointer<IDWriteTextRendererVtbl>? }

typealias DWQueryInterfaceProc = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<GUID>?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> HRESULT
typealias DWAddRefProc = @convention(c) (UnsafeMutableRawPointer?) -> ULONG
typealias DWReleaseProc = @convention(c) (UnsafeMutableRawPointer?) -> ULONG

typealias DWCreateRenderingParamsProc = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> HRESULT
typealias DWCreateCustomRenderingParamsProc = @convention(c) (UnsafeMutableRawPointer?, FLOAT, FLOAT, FLOAT, DWritePixelGeometry, DWriteRenderingMode, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> HRESULT
typealias DWCreateTextFormatProc = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<WCHAR>?, UnsafeMutableRawPointer?, DWriteFontWeight, DWriteFontStyle, DWriteFontStretch, FLOAT, UnsafePointer<WCHAR>?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> HRESULT
typealias DWGetGdiInteropProc = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> HRESULT
typealias DWCreateTextLayoutProc = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<WCHAR>?, UINT32, UnsafeMutableRawPointer?, FLOAT, FLOAT, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> HRESULT

typealias DWSetTextAlignmentProc = @convention(c) (UnsafeMutableRawPointer?, DWriteTextAlignment) -> HRESULT
typealias DWSetParagraphAlignmentProc = @convention(c) (UnsafeMutableRawPointer?, DWriteParagraphAlignment) -> HRESULT
typealias DWSetWordWrappingProc = @convention(c) (UnsafeMutableRawPointer?, DWriteWordWrapping) -> HRESULT
typealias DWSetLineSpacingProc = @convention(c) (UnsafeMutableRawPointer?, DWriteLineSpacingMethod, FLOAT, FLOAT) -> HRESULT
typealias DWDrawTextLayoutProc = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, FLOAT, FLOAT) -> HRESULT
typealias DWGetMetricsProc = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> HRESULT
typealias DWGetOverhangMetricsProc = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> HRESULT
typealias DWHitTestTextPositionProc = @convention(c) (UnsafeMutableRawPointer?, UINT32, WindowsBool, UnsafeMutablePointer<FLOAT>?, UnsafeMutablePointer<FLOAT>?, UnsafeMutableRawPointer?) -> HRESULT
// SetUnderline, SetStrikethrough, SetFontWeight, SetFontSize, SetTypography
// use DWRITE_TEXT_RANGE which is a custom struct not representable in @convention(c).
// These vtable slots are accessed via unsafeBitCast at call sites instead,
// passing startPosition and length as separate UINT32 parameters.
typealias DWGetFontFamilyNameLengthProc = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UINT32>?) -> HRESULT
typealias DWGetFontFamilyNameProc = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<WCHAR>?, UINT32) -> HRESULT

typealias DWCreateBitmapRenderTargetProc = @convention(c) (UnsafeMutableRawPointer?, HDC?, UINT32, UINT32, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> HRESULT
typealias DWBitmapDrawGlyphRunProc = @convention(c) (UnsafeMutableRawPointer?, FLOAT, FLOAT, DWriteMeasuringMode, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, COLORREF, UnsafeMutableRawPointer?) -> HRESULT
typealias DWBitmapGetMemoryDCProc = @convention(c) (UnsafeMutableRawPointer?) -> HDC?
typealias DWBitmapSetPixelsPerDipProc = @convention(c) (UnsafeMutableRawPointer?, FLOAT) -> HRESULT

typealias DWIsPixelSnappingDisabledProc = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutablePointer<WindowsBool>?) -> HRESULT
typealias DWGetCurrentTransformProc = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> HRESULT
typealias DWGetPixelsPerDipProc = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutablePointer<FLOAT>?) -> HRESULT
typealias DWDrawGlyphRunProc = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, FLOAT, FLOAT, DWriteMeasuringMode, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> HRESULT
typealias DWDrawUnderlineProc = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, FLOAT, FLOAT, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> HRESULT
typealias DWDrawStrikethroughProc = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, FLOAT, FLOAT, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> HRESULT
typealias DWDrawInlineObjectProc = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, FLOAT, FLOAT, UnsafeMutableRawPointer?, WindowsBool, WindowsBool, UnsafeMutableRawPointer?) -> HRESULT

struct IDWriteRenderingParamsVtbl {
    var QueryInterface: DWQueryInterfaceProc
    var AddRef: DWAddRefProc
    var Release: DWReleaseProc
    var GetGamma: UnsafeMutableRawPointer?
    var GetEnhancedContrast: UnsafeMutableRawPointer?
    var GetClearTypeLevel: UnsafeMutableRawPointer?
    var GetPixelGeometry: UnsafeMutableRawPointer?
    var GetRenderingMode: UnsafeMutableRawPointer?
}

struct IDWriteTextFormatVtbl {
    var QueryInterface: DWQueryInterfaceProc
    var AddRef: DWAddRefProc
    var Release: DWReleaseProc
    var SetTextAlignment: DWSetTextAlignmentProc
    var SetParagraphAlignment: DWSetParagraphAlignmentProc
    var SetWordWrapping: DWSetWordWrappingProc
    var SetReadingDirection: UnsafeMutableRawPointer?
    var SetFlowDirection: UnsafeMutableRawPointer?
    var SetIncrementalTabStop: UnsafeMutableRawPointer?
    var SetTrimming: UnsafeMutableRawPointer?
    var SetLineSpacing: DWSetLineSpacingProc
    var GetTextAlignment: UnsafeMutableRawPointer?
    var GetParagraphAlignment: UnsafeMutableRawPointer?
    var GetWordWrapping: UnsafeMutableRawPointer?
    var GetReadingDirection: UnsafeMutableRawPointer?
    var GetFlowDirection: UnsafeMutableRawPointer?
    var GetIncrementalTabStop: UnsafeMutableRawPointer?
    var GetTrimming: UnsafeMutableRawPointer?
    var GetLineSpacing: UnsafeMutableRawPointer?
    var GetFontCollection: UnsafeMutableRawPointer?
    var GetFontFamilyNameLength: DWGetFontFamilyNameLengthProc
    var GetFontFamilyName: DWGetFontFamilyNameProc
    var GetFontWeight: UnsafeMutableRawPointer?
    var GetFontStyle: UnsafeMutableRawPointer?
    var GetFontStretch: UnsafeMutableRawPointer?
    var GetFontSize: UnsafeMutableRawPointer?
    var GetLocaleNameLength: UnsafeMutableRawPointer?
    var GetLocaleName: UnsafeMutableRawPointer?
}

struct IDWriteTextLayoutVtbl {
    var QueryInterface: DWQueryInterfaceProc
    var AddRef: DWAddRefProc
    var Release: DWReleaseProc
    var SetTextAlignment: DWSetTextAlignmentProc
    var SetParagraphAlignment: DWSetParagraphAlignmentProc
    var SetWordWrapping: DWSetWordWrappingProc
    var SetReadingDirection: UnsafeMutableRawPointer?
    var SetFlowDirection: UnsafeMutableRawPointer?
    var SetIncrementalTabStop: UnsafeMutableRawPointer?
    var SetTrimming: UnsafeMutableRawPointer?
    var SetLineSpacing: DWSetLineSpacingProc
    var GetTextAlignment: UnsafeMutableRawPointer?
    var GetParagraphAlignment: UnsafeMutableRawPointer?
    var GetWordWrapping: UnsafeMutableRawPointer?
    var GetReadingDirection: UnsafeMutableRawPointer?
    var GetFlowDirection: UnsafeMutableRawPointer?
    var GetIncrementalTabStop: UnsafeMutableRawPointer?
    var GetTrimming: UnsafeMutableRawPointer?
    var GetLineSpacing: UnsafeMutableRawPointer?
    var GetFontCollection: UnsafeMutableRawPointer?
    var GetFontFamilyNameLength: UnsafeMutableRawPointer?
    var GetFontFamilyName: UnsafeMutableRawPointer?
    var GetFontWeight: UnsafeMutableRawPointer?
    var GetFontStyle: UnsafeMutableRawPointer?
    var GetFontStretch: UnsafeMutableRawPointer?
    var GetFontSize: UnsafeMutableRawPointer?
    var GetLocaleNameLength: UnsafeMutableRawPointer?
    var GetLocaleName: UnsafeMutableRawPointer?
    var SetMaxWidth: UnsafeMutableRawPointer?
    var SetMaxHeight: UnsafeMutableRawPointer?
    var SetFontCollection: UnsafeMutableRawPointer?
    var SetFontFamilyName: UnsafeMutableRawPointer?
    var SetFontWeight: UnsafeMutableRawPointer?
    var SetFontStyle: UnsafeMutableRawPointer?
    var SetFontStretch: UnsafeMutableRawPointer?
    var SetFontSize: UnsafeMutableRawPointer?
    var SetUnderline: UnsafeMutableRawPointer?
    var SetStrikethrough: UnsafeMutableRawPointer?
    var SetDrawingEffect: UnsafeMutableRawPointer?
    var SetInlineObject: UnsafeMutableRawPointer?
    var SetTypography: UnsafeMutableRawPointer?
    var SetLocaleName: UnsafeMutableRawPointer?
    var GetMaxWidth: UnsafeMutableRawPointer?
    var GetMaxHeight: UnsafeMutableRawPointer?
    var GetFontCollection2: UnsafeMutableRawPointer?
    var GetFontFamilyNameLength2: UnsafeMutableRawPointer?
    var GetFontFamilyName2: UnsafeMutableRawPointer?
    var GetFontWeight2: UnsafeMutableRawPointer?
    var GetFontStyle2: UnsafeMutableRawPointer?
    var GetFontStretch2: UnsafeMutableRawPointer?
    var GetFontSize2: UnsafeMutableRawPointer?
    var GetUnderline: UnsafeMutableRawPointer?
    var GetStrikethrough: UnsafeMutableRawPointer?
    var GetDrawingEffect: UnsafeMutableRawPointer?
    var GetInlineObject: UnsafeMutableRawPointer?
    var GetTypography: UnsafeMutableRawPointer?
    var GetLocaleNameLength2: UnsafeMutableRawPointer?
    var GetLocaleName2: UnsafeMutableRawPointer?
    var Draw: DWDrawTextLayoutProc
    var GetLineMetrics: UnsafeMutableRawPointer?
    var GetMetrics: DWGetMetricsProc
    var GetOverhangMetrics: DWGetOverhangMetricsProc
    var GetClusterMetrics: UnsafeMutableRawPointer?
    var DetermineMinWidth: UnsafeMutableRawPointer?
    var HitTestPoint: UnsafeMutableRawPointer?
    var HitTestTextPosition: UnsafeMutableRawPointer?
    var HitTestTextRange: UnsafeMutableRawPointer?
}

struct IDWriteGdiInteropVtbl {
    var QueryInterface: DWQueryInterfaceProc
    var AddRef: DWAddRefProc
    var Release: DWReleaseProc
    var CreateFontFromLOGFONT: UnsafeMutableRawPointer?
    var ConvertFontToLOGFONT: UnsafeMutableRawPointer?
    var ConvertFontFaceToLOGFONT: UnsafeMutableRawPointer?
    var CreateFontFaceFromHdc: UnsafeMutableRawPointer?
    var CreateBitmapRenderTarget: DWCreateBitmapRenderTargetProc
}

struct IDWriteBitmapRenderTargetVtbl {
    var QueryInterface: DWQueryInterfaceProc
    var AddRef: DWAddRefProc
    var Release: DWReleaseProc
    var DrawGlyphRun: DWBitmapDrawGlyphRunProc
    var GetMemoryDC: DWBitmapGetMemoryDCProc
    var GetPixelsPerDip: UnsafeMutableRawPointer?
    var SetPixelsPerDip: DWBitmapSetPixelsPerDipProc
    var GetCurrentTransform: UnsafeMutableRawPointer?
    var SetCurrentTransform: UnsafeMutableRawPointer?
    var GetSize: UnsafeMutableRawPointer?
    var Resize: UnsafeMutableRawPointer?
}

struct IDWriteFactoryVtbl {
    var QueryInterface: DWQueryInterfaceProc
    var AddRef: DWAddRefProc
    var Release: DWReleaseProc
    var GetSystemFontCollection: UnsafeMutableRawPointer?
    var CreateCustomFontCollection: UnsafeMutableRawPointer?
    var RegisterFontCollectionLoader: UnsafeMutableRawPointer?
    var UnregisterFontCollectionLoader: UnsafeMutableRawPointer?
    var CreateFontFileReference: UnsafeMutableRawPointer?
    var CreateCustomFontFileReference: UnsafeMutableRawPointer?
    var CreateFontFace: UnsafeMutableRawPointer?
    var CreateRenderingParams: DWCreateRenderingParamsProc
    var CreateMonitorRenderingParams: UnsafeMutableRawPointer?
    var CreateCustomRenderingParams: DWCreateCustomRenderingParamsProc
    var RegisterFontFileLoader: UnsafeMutableRawPointer?
    var UnregisterFontFileLoader: UnsafeMutableRawPointer?
    var CreateTextFormat: DWCreateTextFormatProc
    var CreateTypography: UnsafeMutableRawPointer?
    var GetGdiInterop: DWGetGdiInteropProc
    var CreateTextLayout: DWCreateTextLayoutProc
    var CreateGdiCompatibleTextLayout: UnsafeMutableRawPointer?
    var CreateEllipsisTrimmingSign: UnsafeMutableRawPointer?
    var CreateTextAnalyzer: UnsafeMutableRawPointer?
    var CreateNumberSubstitution: UnsafeMutableRawPointer?
    var CreateGlyphRunAnalysis: UnsafeMutableRawPointer?
}

struct IDWriteTextRendererVtbl {
    var QueryInterface: DWQueryInterfaceProc
    var AddRef: DWAddRefProc
    var Release: DWReleaseProc
    var IsPixelSnappingDisabled: DWIsPixelSnappingDisabledProc
    var GetCurrentTransform: DWGetCurrentTransformProc
    var GetPixelsPerDip: DWGetPixelsPerDipProc
    var DrawGlyphRun: DWDrawGlyphRunProc
    var DrawUnderline: DWDrawUnderlineProc
    var DrawStrikethrough: DWDrawStrikethroughProc
    var DrawInlineObject: DWDrawInlineObjectProc
}

let iidIDWriteFactory = makeGUID(data1: 0xB859EE5A, data2: 0xD838, data3: 0x4B5B, data4: (0xA2, 0xE8, 0x1A, 0xDC, 0x7D, 0x93, 0xDB, 0x48))
let iidIDWritePixelSnapping = makeGUID(data1: 0xEAF3A2DA, data2: 0xECF4, data3: 0x4D24, data4: (0xB6, 0x44, 0xB3, 0x4F, 0x68, 0x42, 0x02, 0x4B))
let iidIDWriteTextRenderer = makeGUID(data1: 0xEF8A8135, data2: 0x5CC6, data3: 0x45FE, data4: (0x88, 0x25, 0xC5, 0xA0, 0x72, 0x4E, 0xB8, 0x19))
let iidIUnknownDirectWrite = makeGUID(data1: 0x00000000, data2: 0x0000, data3: 0x0000, data4: (0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46))

func makeGUID(data1: UInt32, data2: UInt16, data3: UInt16, data4: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)) -> GUID {
    var guid = GUID()
    guid.Data1 = data1
    guid.Data2 = data2
    guid.Data3 = data3
    guid.Data4 = data4
    return guid
}

func isSuccess(_ hr: HRESULT) -> Bool {
    hr >= 0
}

func guidEquals(_ lhs: GUID, _ rhs: GUID) -> Bool {
    withUnsafeBytes(of: lhs.Data4) { lhsBytes in
        withUnsafeBytes(of: rhs.Data4) { rhsBytes in
            lhs.Data1 == rhs.Data1 && lhs.Data2 == rhs.Data2 && lhs.Data3 == rhs.Data3 && lhsBytes.elementsEqual(rhsBytes)
        }
    }
}

func releaseDirectWriteCOM<T>(_ pointer: inout UnsafeMutablePointer<T>?) {
    guard let rawPointer = pointer else {
        return
    }

    let unknown = UnsafeMutableRawPointer(rawPointer).assumingMemoryBound(to: IUnknown.self)
    _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
    pointer = nil
}
