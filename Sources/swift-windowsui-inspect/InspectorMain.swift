import Dispatch
import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsRendererD3D11
import SwiftWindowsUI
import WinSwiftUI

@main
struct SwiftWindowsUIInspector {
    @MainActor
    static func main() {
        let textCapabilities = TextSystem.capabilities()
        let renderBackend = DefaultRenderBackendFactory.make()
        let batchBackend = DefaultRenderBackendFactory.makeBatchBackend()

        let runtime = makeSampleRuntime()
        let frame = runtime.renderFrame()
        let bridgedScene = runtime.renderScene()
        let paintedScene = ScenePainter.paint(
            root: runtime.root,
            clearColor: runtime.clearColor,
            surfaceSize: runtime.root.frame.size
        )
        let pathProbeFrame = makePathProbeFrame()
        let pathProbeCounts = CommandCounts(pathProbeFrame.commands)
        let pathProbePath = makePathProbePath()
        let textProbeCounts = CommandCounts(makeTextProbeFrame().commands)
        let blurProbeCounts = CommandCounts(makeBlurProbeFrame().commands)
        let controlProbeRuntime = makeControlProbeRuntime()
        let controlProbeCounts = CommandCounts(controlProbeRuntime.renderFrame().commands)
        let controlProbeFocusableCount = countFocusableNodes(controlProbeRuntime.root)
        let winSwiftUIProbe = WinSwiftUIInspection.snapshot(
            of: WinSwiftUIProbeView(),
            size: Size(width: 360, height: 260),
            maximumTextSamples: 40
        )
        let textInputProbeValue = runTextInputProbe()
        let scrollStress = runScrollStressProbe()
        let clipProbeScene = GPUIScene(from: makeClipProbeFrame(), surfaceSize: Size(width: 240, height: 180))
        let commandCounts = CommandCounts(frame.commands)
        let wantsJSON = CommandLine.arguments.contains("--json")
        let wantsVerification = CommandLine.arguments.contains("--verify")
        let failures = wantsVerification
            ? verificationFailures(
                batchBackendName: batchBackend?.backendDisplayName,
                sampleCommandCounts: commandCounts,
                bridgedScene: bridgedScene,
                paintedScene: paintedScene,
                pathProbeCounts: pathProbeCounts,
                textProbeCounts: textProbeCounts,
                blurProbeCounts: blurProbeCounts,
                controlProbeFocusableCount: controlProbeFocusableCount,
                winSwiftUIProbe: winSwiftUIProbe,
                textInputProbeValue: textInputProbeValue,
                scrollStress: scrollStress,
                clipProbeScene: clipProbeScene
            )
            : []
        let report = InspectorReport(
            renderBackend: renderBackend.backendStatusDescription,
            batchBackend: batchBackend?.backendDisplayName,
            textBackend: textCapabilities.renderingLabel,
            renderFrame: CommandSummary(total: frame.commands.count, counts: commandCounts),
            gpuSceneBridge: SceneSummary(layers: bridgedScene.layers.count, primitives: bridgedScene.primitiveCount),
            scenePainter: ScenePainterSummary(
                layers: paintedScene.layers.count,
                primitives: paintedScene.primitiveCount,
                quads: paintedScene.totalQuads,
                shadows: paintedScene.totalShadows,
                glyphs: paintedScene.totalGlyphs,
                images: paintedScene.totalImages
            ),
            pathProbe: PathProbeSummary(fillPath: pathProbeCounts.fillPath, strokePath: pathProbeCounts.strokePath, segments: pathProbePath.segments.count),
            textProbe: TextProbeSummary(drawText: textProbeCounts.drawText),
            blurProbe: BlurProbeSummary(applyBlur: blurProbeCounts.applyBlur),
            controlProbe: ControlProbeSummary(focusable: controlProbeFocusableCount, fillRect: controlProbeCounts.fillRect, drawBitmap: controlProbeCounts.drawBitmap),
            winSwiftUIProbe: WinSwiftUIProbeSummary(
                nodes: winSwiftUIProbe.nodeCount,
                textNodes: winSwiftUIProbe.textNodeCount,
                focusableNodes: winSwiftUIProbe.focusableNodeCount,
                rootLayoutKind: winSwiftUIProbe.rootLayoutKind,
                maxDepth: winSwiftUIProbe.maxDepth,
                renderCommands: winSwiftUIProbe.renderCommands.total,
                textSamples: winSwiftUIProbe.textSamples
            ),
            textInputProbe: textInputProbeValue,
            scrollStress: scrollStress,
            clipStackProbe: clipSummary(clipProbeScene.layers.first?.quads.first?.clipRect),
            verification: wantsVerification ? VerificationSummary(passed: failures.isEmpty, failures: failures) : nil
        )

        if wantsJSON {
            printJSON(report)
        } else {
            printHumanReport(report)
        }

        if wantsVerification {
            if failures.isEmpty {
                if !wantsJSON {
                    print("Verification: passed")
                }
            } else {
                if !wantsJSON {
                    print("Verification: failed")
                    for failure in failures {
                        print("  - \(failure)")
                    }
                }
                fatalError("swift-windowsui-inspect verification failed")
            }
        }
    }
}

@MainActor
private func makeSampleRuntime() -> RetainedViewRuntime {
    let title = Controls.label(
        "WINSWIFTUI INSPECT",
        color: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 1.0),
        scale: 2.4,
        weight: .bold,
        alignment: .leading,
        lineBreakMode: .truncateTail,
        maximumNumberOfLines: 1
    )
    let subtitle = Controls.label(
        "RENDERFRAME AND BATCH SCENE DIAGNOSTICS",
        color: Color(red: 0.60, green: 0.70, blue: 0.82, alpha: 1.0),
        scale: 1.6,
        alignment: .leading,
        lineBreakMode: .truncateTail,
        maximumNumberOfLines: 1
    )
    let card = ViewNode(
        frame: Rect(x: 20, y: 20, width: 340, height: 128),
        backgroundGradient: LinearGradient(
            startColor: Color(red: 0.18, green: 0.24, blue: 0.34, alpha: 0.92),
            endColor: Color(red: 0.08, green: 0.11, blue: 0.18, alpha: 0.96)
        ),
        borderColor: Color(red: 0.85, green: 0.92, blue: 1.0, alpha: 0.24),
        borderWidth: 1,
        shadowColor: Color(red: 0.02, green: 0.04, blue: 0.08, alpha: 0.22),
        shadowOffset: Point(x: 0, y: 12),
        shadowSpread: 10,
        cornerRadius: 18,
        layoutMode: .stack(
            .vertical(
                spacing: 8,
                padding: EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20),
                alignment: .leading
            )
        ),
        isHitTestVisible: false,
        children: [title, subtitle]
    )
    let root = ViewNode(
        frame: Rect(x: 0, y: 0, width: 380, height: 180),
        backgroundColor: Color(red: 0.06, green: 0.08, blue: 0.12, alpha: 1.0),
        isHitTestVisible: false,
        children: [card]
    )
    return RetainedViewRuntime(
        clearColor: Color(red: 0.06, green: 0.08, blue: 0.12, alpha: 1.0),
        root: root,
        displayScale: 1.0
    )
}

private struct CommandCounts {
    var fillRect = 0
    var drawBitmap = 0
    var fillPath = 0
    var strokePath = 0
    var applyBlur = 0
    var drawText = 0
    var clipOperations = 0

    init(_ commands: [RenderCommand]) {
        for command in commands {
            switch command {
            case .fillRect:
                fillRect += 1
            case .drawBitmap:
                drawBitmap += 1
            case .fillPath:
                fillPath += 1
            case .strokePath:
                strokePath += 1
            case .applyBlur:
                applyBlur += 1
            case .drawText:
                drawText += 1
            case .pushClip, .popClip:
                clipOperations += 1
            }
        }
    }
}

private struct InspectorReport: Encodable {
    var renderBackend: String
    var batchBackend: String?
    var textBackend: String
    var renderFrame: CommandSummary
    var gpuSceneBridge: SceneSummary
    var scenePainter: ScenePainterSummary
    var pathProbe: PathProbeSummary
    var textProbe: TextProbeSummary
    var blurProbe: BlurProbeSummary
    var controlProbe: ControlProbeSummary
    var winSwiftUIProbe: WinSwiftUIProbeSummary
    var textInputProbe: String
    var scrollStress: ScrollStressResult
    var clipStackProbe: ClipSummary?
    var verification: VerificationSummary?
}

private struct CommandSummary: Encodable {
    var total: Int
    var fillRect: Int
    var drawBitmap: Int
    var fillPath: Int
    var strokePath: Int
    var applyBlur: Int
    var drawText: Int
    var clipOperations: Int

    init(total: Int, counts: CommandCounts) {
        self.total = total
        self.fillRect = counts.fillRect
        self.drawBitmap = counts.drawBitmap
        self.fillPath = counts.fillPath
        self.strokePath = counts.strokePath
        self.applyBlur = counts.applyBlur
        self.drawText = counts.drawText
        self.clipOperations = counts.clipOperations
    }
}

private struct SceneSummary: Encodable {
    var layers: Int
    var primitives: Int
}

private struct ScenePainterSummary: Encodable {
    var layers: Int
    var primitives: Int
    var quads: Int
    var shadows: Int
    var glyphs: Int
    var images: Int
}

private struct PathProbeSummary: Encodable {
    var fillPath: Int
    var strokePath: Int
    var segments: Int
}

private struct TextProbeSummary: Encodable {
    var drawText: Int
}

private struct BlurProbeSummary: Encodable {
    var applyBlur: Int
}

private struct ControlProbeSummary: Encodable {
    var focusable: Int
    var fillRect: Int
    var drawBitmap: Int
}

private struct WinSwiftUIProbeSummary: Encodable {
    var nodes: Int
    var textNodes: Int
    var focusableNodes: Int
    var rootLayoutKind: String
    var maxDepth: Int
    var renderCommands: Int
    var textSamples: [String]
}

private struct ClipSummary: Encodable {
    var x: Float
    var y: Float
    var width: Float
    var height: Float
}

private struct VerificationSummary: Encodable {
    var passed: Bool
    var failures: [String]
}

private func printJSON(_ report: InspectorReport) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
        let data = try encoder.encode(report)
        guard let json = String(data: data, encoding: .utf8) else {
            fatalError("swift-windowsui-inspect could not encode UTF-8 JSON")
        }
        print(json)
    } catch {
        fatalError("swift-windowsui-inspect JSON encoding failed: \(error)")
    }
}

private func printHumanReport(_ report: InspectorReport) {
    print("Swift Windows UI Inspector")
    print("Render backend: \(report.renderBackend)")
    print("Batch backend: \(report.batchBackend ?? "unavailable")")
    print("Text backend: \(report.textBackend)")
    print("RenderFrame commands: \(report.renderFrame.total)")
    print("  fillRect: \(report.renderFrame.fillRect)")
    print("  drawBitmap: \(report.renderFrame.drawBitmap)")
    print("  fillPath: \(report.renderFrame.fillPath)")
    print("  strokePath: \(report.renderFrame.strokePath)")
    print("  applyBlur: \(report.renderFrame.applyBlur)")
    print("  drawText: \(report.renderFrame.drawText)")
    print("  clip ops: \(report.renderFrame.clipOperations)")
    print("GPUIScene bridge: \(report.gpuSceneBridge.layers) layers, \(report.gpuSceneBridge.primitives) primitives")
    print("ScenePainter batch: \(report.scenePainter.layers) layers, \(report.scenePainter.primitives) primitives")
    print("  quads: \(report.scenePainter.quads)")
    print("  shadows: \(report.scenePainter.shadows)")
    print("  glyphs: \(report.scenePainter.glyphs)")
    print("  images: \(report.scenePainter.images)")
    print("Path probe: \(report.pathProbe.fillPath) fill, \(report.pathProbe.strokePath) stroke, \(report.pathProbe.segments) segments")
    print("Text probe: \(report.textProbe.drawText) drawText command")
    print("Blur probe: \(report.blurProbe.applyBlur) applyBlur command")
    print("Control probe: \(report.controlProbe.focusable) focusable, \(report.controlProbe.fillRect) fills, \(report.controlProbe.drawBitmap) bitmaps")
    print("WinSwiftUI probe: \(report.winSwiftUIProbe.nodes) nodes, \(report.winSwiftUIProbe.textNodes) text, \(report.winSwiftUIProbe.focusableNodes) focusable")
    print("  layout: \(report.winSwiftUIProbe.rootLayoutKind), depth: \(report.winSwiftUIProbe.maxDepth), commands: \(report.winSwiftUIProbe.renderCommands)")
    print("  text: \(report.winSwiftUIProbe.textSamples.joined(separator: ", "))")
    print("Text input probe: \(report.textInputProbe)")
    print("Scroll stress: \(report.scrollStress.rowCount) rows -> \(report.scrollStress.commandCount) commands in \(formatMilliseconds(report.scrollStress.elapsedMilliseconds)) ms")
    print("Clip stack probe: \(formatClip(report.clipStackProbe))")
}

private func makeClipProbeFrame() -> RenderFrame {
    RenderFrame(
        clearColor: .black,
        commands: [
            .pushClip(ClipCommand(shape: .rect(Rect(x: 0, y: 0, width: 120, height: 120), cornerRadius: 0))),
            .pushClip(ClipCommand(
                shape: .rect(Rect(x: 80, y: 40, width: 90, height: 80), cornerRadius: 0),
                operation: .replace
            )),
            .fillRect(FillRectCommand(
                rect: Rect(x: 0, y: 0, width: 240, height: 180),
                color: Color(red: 0.45, green: 0.74, blue: 0.98, alpha: 1.0),
                clipRect: Rect(x: 100, y: 50, width: 80, height: 80)
            )),
            .popClip,
            .popClip,
        ]
    )
}

private func makePathProbePath() -> RenderPath {
    var path = RenderPath()
    path.move(to: Point(x: 32, y: 120))
    path.addCubicCurve(
        to: Point(x: 208, y: 120),
        control1: Point(x: 80, y: 32),
        control2: Point(x: 160, y: 32)
    )
    path.addLine(to: Point(x: 180, y: 152))
    path.addLine(to: Point(x: 60, y: 152))
    path.close()
    return path
}

private func makePathProbeFrame() -> RenderFrame {
    let path = makePathProbePath()
    return RenderFrame(
        clearColor: .black,
        commands: [
            .fillPath(FillPathCommand(path: path, color: Color(red: 0.42, green: 0.68, blue: 0.96, alpha: 0.72))),
            .strokePath(StrokePathCommand(
                path: path,
                color: Color(red: 0.94, green: 0.98, blue: 1.0, alpha: 1.0),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )),
        ]
    )
}

private func makeTextProbeFrame() -> RenderFrame {
    RenderFrame(
        clearColor: .black,
        commands: [
            .drawText(DrawTextCommand(
                text: "DIRECTWRITE COMMAND",
                position: Point(x: 24, y: 24),
                fontName: "Segoe UI",
                fontSize: 18,
                fontWeight: .semibold,
                color: Color(red: 0.92, green: 0.96, blue: 1.0, alpha: 1.0),
                maxWidth: 240
            )),
        ]
    )
}

private func makeBlurProbeFrame() -> RenderFrame {
    RenderFrame(
        clearColor: .black,
        commands: [
            .fillRect(FillRectCommand(
                rect: Rect(x: 0, y: 0, width: 180, height: 120),
                color: Color(red: 0.12, green: 0.18, blue: 0.28, alpha: 1.0)
            )),
            .applyBlur(BlurCommand(region: Rect(x: 24, y: 20, width: 132, height: 72), radius: 10)),
        ]
    )
}

@MainActor
private func makeControlProbeRuntime() -> RetainedViewRuntime {
    let root = ViewNode(
        frame: Rect(x: 0, y: 0, width: 260, height: 140),
        backgroundColor: Color(red: 0.06, green: 0.08, blue: 0.12, alpha: 1.0),
        layoutMode: .stack(
            .vertical(
                spacing: 12,
                padding: EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18),
                alignment: .stretch
            )
        ),
        isHitTestVisible: false
    )
    let runtime = RetainedViewRuntime(
        clearColor: Color(red: 0.06, green: 0.08, blue: 0.12, alpha: 1.0),
        root: root,
        displayScale: 1.0
    )

    root.addChild(Controls.toggle(runtime: runtime, isOn: true))
    root.addChild(Controls.textField(runtime: runtime, text: "Filter", placeholder: "Search"))
    root.addChild(Controls.slider(runtime: runtime, value: 0.42, preferredSize: Size(width: 220, height: 28)))
    root.addChild(Controls.progressBar(value: 0.64, preferredSize: Size(width: 220, height: 8)))

    return runtime
}

@MainActor
private func runTextInputProbe() -> String {
    var value = ""
    let root = ViewNode(
        frame: Rect(x: 0, y: 0, width: 240, height: 60),
        isHitTestVisible: false
    )
    let runtime = RetainedViewRuntime(root: root, displayScale: 1.0)
    root.addChild(
        Controls.textField(
            runtime: runtime,
            text: "",
            placeholder: "Search",
            onTextChanged: { value = $0 }
        )
    )

    runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))
    runtime.textInput("ABC")
    runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.leftArrow.rawValue))
    runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.leftArrow.rawValue))
    runtime.textInput("x")
    runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.delete.rawValue))
    return value
}

@MainActor
private func countFocusableNodes(_ node: ViewNode) -> Int {
    let ownCount = node.isFocusable ? 1 : 0
    return ownCount + node.children.reduce(0) { $0 + countFocusableNodes($1) }
}

private struct ScrollStressResult: Encodable {
    var rowCount: Int
    var commandCount: Int
    var elapsedMilliseconds: Double
}

@MainActor
private func runScrollStressProbe(rowCount: Int = 500) -> ScrollStressResult {
    let runtime = makeScrollStressRuntime(rowCount: rowCount)
    let start = DispatchTime.now().uptimeNanoseconds
    let frame = runtime.renderFrame()
    let elapsed = DispatchTime.now().uptimeNanoseconds - start

    return ScrollStressResult(
        rowCount: rowCount,
        commandCount: frame.commands.count,
        elapsedMilliseconds: Double(elapsed) / 1_000_000
    )
}

@MainActor
private func makeScrollStressRuntime(rowCount: Int) -> RetainedViewRuntime {
    let rows = (0..<rowCount).map { index in
        Controls.panel(
            preferredSize: Size(width: 0, height: 24),
            backgroundColor: index.isMultiple(of: 2)
                ? Color(red: 0.16, green: 0.20, blue: 0.28, alpha: 1.0)
                : Color(red: 0.11, green: 0.15, blue: 0.22, alpha: 1.0),
            cornerRadius: 6,
            isHitTestVisible: false
        )
    }

    let scrollPanel = Controls.scrollPanel(
        axis: .vertical,
        frame: Rect(x: 0, y: 0, width: 320, height: 220),
        stackLayout: .vertical(spacing: 2, alignment: .stretch),
        scrollIndicatorThickness: 5,
        isHitTestVisible: true,
        children: rows
    )
    scrollPanel.scrollOffset = 6_000

    let root = ViewNode(
        frame: Rect(x: 0, y: 0, width: 320, height: 220),
        isHitTestVisible: false,
        children: [scrollPanel]
    )

    return RetainedViewRuntime(root: root, displayScale: 1.0)
}

private func formatMilliseconds(_ value: Double) -> String {
    let rounded = (value * 1_000).rounded() / 1_000
    return "\(rounded)"
}

private func formatClip(_ clip: (Float, Float, Float, Float)?) -> String {
    guard let clip else {
        return "none"
    }

    return "x=\(clip.0) y=\(clip.1) w=\(clip.2) h=\(clip.3)"
}

private func formatClip(_ clip: ClipSummary?) -> String {
    guard let clip else {
        return "none"
    }

    return "x=\(clip.x) y=\(clip.y) w=\(clip.width) h=\(clip.height)"
}

private func clipSummary(_ clip: (Float, Float, Float, Float)?) -> ClipSummary? {
    guard let clip else {
        return nil
    }

    return ClipSummary(x: clip.0, y: clip.1, width: clip.2, height: clip.3)
}

private func verificationFailures(
    batchBackendName: String?,
    sampleCommandCounts: CommandCounts,
    bridgedScene: GPUIScene,
    paintedScene: GPUIScene,
    pathProbeCounts: CommandCounts,
    textProbeCounts: CommandCounts,
    blurProbeCounts: CommandCounts,
    controlProbeFocusableCount: Int,
    winSwiftUIProbe: WinSwiftUIInspectionSnapshot,
    textInputProbeValue: String,
    scrollStress: ScrollStressResult,
    clipProbeScene: GPUIScene
) -> [String] {
    var failures: [String] = []

    if batchBackendName == nil {
        failures.append("batch backend is unavailable")
    }
    if sampleCommandCounts.fillRect == 0 {
        failures.append("sample retained tree emitted no fillRect commands")
    }
    if sampleCommandCounts.drawBitmap == 0 {
        failures.append("sample retained tree emitted no bitmap text commands")
    }
    if bridgedScene.primitiveCount == 0 {
        failures.append("RenderFrame -> GPUIScene bridge emitted no primitives")
    }
    if paintedScene.totalQuads == 0 {
        failures.append("ScenePainter emitted no quads")
    }
    if pathProbeCounts.fillPath != 1 || pathProbeCounts.strokePath != 1 {
        failures.append("path probe did not emit one fillPath and one strokePath command")
    }
    if textProbeCounts.drawText != 1 {
        failures.append("text probe did not emit one drawText command")
    }
    if blurProbeCounts.applyBlur != 1 {
        failures.append("blur probe did not emit one applyBlur command")
    }
    if controlProbeFocusableCount < 3 {
        failures.append("retained control probe exposed fewer than three focusable controls")
    }
    if winSwiftUIProbe.nodeCount < 15 || winSwiftUIProbe.textNodeCount < 5 || winSwiftUIProbe.renderCommands.total == 0 {
        failures.append("WinSwiftUI probe did not produce the expected retained tree/render frame")
    }
    if !winSwiftUIProbe.textSamples.contains("DECLARATIVE INSPECTOR") {
        failures.append("WinSwiftUI probe text samples are missing the title")
    }
    if textInputProbeValue != "AxC" {
        failures.append("text input probe expected AxC, got \(textInputProbeValue)")
    }
    if scrollStress.commandCount > 40 {
        failures.append("scroll stress emitted \(scrollStress.commandCount) commands; expected culling to keep it at or below 40")
    }
    if !clipMatches(clipProbeScene.layers.first?.quads.first?.clipRect, x: 100, y: 50, width: 70, height: 70) {
        failures.append("clip probe did not resolve to the expected intersection")
    }

    return failures
}

private func clipMatches(
    _ clip: (Float, Float, Float, Float)?,
    x: Float,
    y: Float,
    width: Float,
    height: Float,
    tolerance: Float = 0.001
) -> Bool {
    guard let clip else {
        return false
    }

    return abs(clip.0 - x) <= tolerance
        && abs(clip.1 - y) <= tolerance
        && abs(clip.2 - width) <= tolerance
        && abs(clip.3 - height) <= tolerance
}

@MainActor
private struct WinSwiftUIProbeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DECLARATIVE INSPECTOR")
                .font(.system(size: 2.1, weight: .bold))
                .lineLimit(1)

            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                Text("WINSWIFTUI TO RETAINED TREE")
                    .lineLimit(1)
            }

            Button("DISABLED ACTION") {}
                .disabled(true)

            Toggle("LIVE SWITCH", isOn: Binding(get: { true }, set: { _ in }))

            ProgressView(value: 0.68)

            Form {
                Section("FORM STATUS") {
                    LabeledContent("ROW MODE", value: "INSPECTED")
                    Toggle("INSPECTED ROW", isOn: Binding(get: { true }, set: { _ in }))
                    Stepper("STEP COUNT", value: Binding(get: { 2 }, set: { _ in }), in: 0...5)
                }
                GroupBox("GROUP BOX") {
                    Text("INSPECTED DETAIL")
                    ControlGroup {
                        Button("RUN") {}
                        Button("STOP") {}
                        Menu("ACTIONS", systemImage: "ellipsis") {
                            Button("MENU ACTION") {}
                        }
                    }
                    DisclosureGroup("MORE DETAIL", isExpanded: Binding(get: { true }, set: { _ in })) {
                        Text("DISCLOSED ROW")
                    }
                }
            }
            .frame(height: 126)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    Text("LAZY ROW 1")
                    Text("LAZY ROW 2")
                    Text("LAZY ROW 3")
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                    ],
                    spacing: 4
                ) {
                    Text("GRID A")
                    Text("GRID B")
                    Text("GRID C")
                    Text("GRID D")
                }
            }
            .frame(height: 96)

            TabView(selection: Binding(get: { "summary" }, set: { _ in })) {
                Text("TAB SUMMARY")
                    .tabItem {
                        Text("Summary")
                    }
                    .tag("summary")
                Text("TAB DETAIL")
                    .tabItem {
                        Label("Detail", systemImage: "bolt.fill")
                    }
                    .tag("detail")
            }
            .frame(height: 86)

            NavigationStack {
                NavigationLink("Inspector Detail") {
                    Text("INSPECTOR DESTINATION")
                }
            }
            .navigationTitle("Inspector")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Inspect") {}
                }
            }
            .frame(height: 132)

            NavigationSplitView {
                Text("NAV SIDEBAR")
            } content: {
                Text("NAV CONTENT")
            } detail: {
                Text("NAV DETAIL")
            }
            .frame(height: 92)
        }
        .padding(16)
        .foregroundColor(Color(red: 0.92, green: 0.96, blue: 1.0, alpha: 1.0))
        .font(.system(size: 1.5, weight: .semibold))
        .background(LinearGradient(
            colors: [
                Color(red: 0.18, green: 0.24, blue: 0.34, alpha: 0.94),
                Color(red: 0.07, green: 0.10, blue: 0.16, alpha: 0.98),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ))
        .cornerRadius(18)
    }
}

private extension GPUIScene {
    var totalQuads: Int {
        layers.reduce(0) { $0 + $1.quads.count }
    }

    var totalShadows: Int {
        layers.reduce(0) { $0 + $1.shadows.count }
    }

    var totalGlyphs: Int {
        layers.reduce(0) { $0 + $1.glyphs.count }
    }

    var totalImages: Int {
        layers.reduce(0) { $0 + $1.images.count }
    }
}
