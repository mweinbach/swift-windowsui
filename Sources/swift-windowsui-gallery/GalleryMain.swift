import Foundation
import SwiftWindowsCore
import SwiftWindowsDemo
import SwiftWindowsGraphics
import SwiftWindowsUI
import WinSDK
import WinSwiftUI

@main
struct SwiftWindowsUIGalleryTool {
    @MainActor
    static func main() async throws {
        // Minimal additive CLI:
        //   --entries <csv>     only render the listed entry ids
        //   --output-dir <path> write PNGs/index somewhere else
        // Defaults keep the historical behavior (all entries, artifacts/gallery).
        var outputDirPath = "artifacts/gallery"
        var entryFilter: Set<String>?
        var bitmapFontAttributionDirectory: String?
        var bitmapFontAttributionInvocation: String?
        var bitmapFontAttributionVersion = NativeBitmapFontAttributionVersion.v1
        var bitmapFontVersionSupplied = false
        var geometryDiagnosticDirectory: String?
        var geometryDiagnosticInvocation: String?
        var rawEntryFilter: [String]?
        var entryArgumentCount = 0
        var ignoredArgumentEncountered = false
        var malformedOutputArgumentEncountered = false
        var argumentIndex = 1
        let arguments = CommandLine.arguments
        let geometryFlagsAttempted = arguments.dropFirst().contains {
            $0.hasPrefix("--geometry-diagnostics")
        }
        while argumentIndex < arguments.count {
            let argument = arguments[argumentIndex]
            if argument == "--entries" { entryArgumentCount += 1 }
            if argument == "--output-dir" {
                if argumentIndex + 1 >= arguments.count
                    || arguments[argumentIndex + 1].hasPrefix("--")
                    || arguments[argumentIndex + 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    // Remember every malformed occurrence, including one overwritten by a later output-dir.
                    malformedOutputArgumentEncountered = true
                }
            }
            if argument == "--output-dir", argumentIndex + 1 < arguments.count {
                outputDirPath = arguments[argumentIndex + 1]
                argumentIndex += 1
            } else if argument == "--entries", argumentIndex + 1 < arguments.count {
                let ids = arguments[argumentIndex + 1]
                    .split(separator: ",", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                rawEntryFilter = ids
                entryFilter = Set(ids.filter { !$0.isEmpty })
                argumentIndex += 1
            } else if argument == "--bitmap-font-attribution-dir" {
                guard bitmapFontAttributionDirectory == nil, argumentIndex + 1 < arguments.count else {
                    throw GalleryError.invalidBitmapFontAttribution
                }
                bitmapFontAttributionDirectory = arguments[argumentIndex + 1]
                argumentIndex += 1
            } else if argument == "--bitmap-font-attribution-invocation" {
                guard bitmapFontAttributionInvocation == nil, argumentIndex + 1 < arguments.count else {
                    throw GalleryError.invalidBitmapFontAttribution
                }
                bitmapFontAttributionInvocation = arguments[argumentIndex + 1]
                argumentIndex += 1
            } else if argument == "--bitmap-font-attribution-version" {
                guard !bitmapFontVersionSupplied, argumentIndex + 1 < arguments.count,
                    ["1", "2"].contains(arguments[argumentIndex + 1]),
                    let value = Int(arguments[argumentIndex + 1]),
                    let version = NativeBitmapFontAttributionVersion(rawValue: value)
                else {
                    throw GalleryError.invalidBitmapFontAttribution
                }
                bitmapFontVersionSupplied = true
                bitmapFontAttributionVersion = version
                argumentIndex += 1
            } else if argument == "--geometry-diagnostics-dir" {
                guard geometryDiagnosticDirectory == nil, argumentIndex + 1 < arguments.count,
                    !arguments[argumentIndex + 1].hasPrefix("--")
                else { throw GalleryError.invalidGeometryDiagnostics }
                geometryDiagnosticDirectory = arguments[argumentIndex + 1]
                argumentIndex += 1
            } else if argument == "--geometry-diagnostics-invocation" {
                guard geometryDiagnosticInvocation == nil, argumentIndex + 1 < arguments.count,
                    !arguments[argumentIndex + 1].hasPrefix("--")
                else { throw GalleryError.invalidGeometryDiagnostics }
                geometryDiagnosticInvocation = arguments[argumentIndex + 1]
                argumentIndex += 1
            } else if argument.hasPrefix("--geometry-diagnostics") {
                throw GalleryError.invalidGeometryDiagnostics
            } else {
                // Preserve ordinary CLI permissiveness, but refuse these
                // arguments when a strict diagnostic invocation was requested.
                ignoredArgumentEncountered = true
            }
            argumentIndex += 1
        }

        let geometryOptions = try GalleryGeometryCLIOptions.validate(
            directory: geometryDiagnosticDirectory, invocationID: geometryDiagnosticInvocation,
            rawEntries: rawEntryFilter, entryArgumentCount: entryArgumentCount,
            bitmapArgumentsPresent: bitmapFontAttributionDirectory != nil
                || bitmapFontAttributionInvocation != nil || bitmapFontVersionSupplied
        )
        guard !geometryFlagsAttempted || geometryOptions != nil else {
            throw GalleryError.invalidGeometryDiagnostics
        }
        let geometryOverrideState: String?
        if geometryOptions != nil {
            guard !ignoredArgumentEncountered, !malformedOutputArgumentEncountered else {
                throw GalleryError.invalidGeometryDiagnostics
            }
            let override = ProcessInfo.processInfo.environment["SWIFT_WINDOWSUI_CLASSIC_UI_FONT"]
            guard override == nil || override == "1" else { throw GalleryError.invalidGeometryDiagnostics }
            geometryOverrideState = override == nil ? "absent" : "1"
        } else {
            geometryOverrideState = nil
        }
        let outputDir = URL(fileURLWithPath: outputDirPath)
        let fontAttributionOutput: URL?
        if let directory = bitmapFontAttributionDirectory, let invocation = bitmapFontAttributionInvocation {
            let allowed = Set([
                NativeBitmapFontFixture.symbolPalette.rawValue, NativeBitmapFontFixture.stepper.rawValue,
            ])
            guard let entryFilter, !entryFilter.isEmpty, entryFilter.isSubset(of: allowed),
                invocation.utf8.count == 32,
                invocation.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                !directory.isEmpty
            else {
                throw GalleryError.invalidBitmapFontAttribution
            }
            // A dedicated directory must be created atomically. Existing
            // native sidecars must never acquire a new invocation's identity.
            let directoryURL = URL(fileURLWithPath: directory).standardizedFileURL
            let created = directoryURL.path.withCString(encodedAs: UTF16.self) { CreateDirectoryW($0, nil) }
            guard created else { throw GalleryError.bitmapFontAttributionOutputUnavailable }
            for id in entryFilter {
                guard !FileManager.default.fileExists(atPath: outputDir.appendingPathComponent("\(id).png").path) else {
                    throw GalleryError.bitmapFontAttributionOutputUnavailable
                }
            }
            fontAttributionOutput = directoryURL
        } else if bitmapFontAttributionDirectory != nil || bitmapFontAttributionInvocation != nil
            || bitmapFontVersionSupplied
        {
            throw GalleryError.invalidBitmapFontAttribution
        } else {
            fontAttributionOutput = nil
        }
        let geometryOutput: URL?
        if let geometryOptions {
            let directory = URL(fileURLWithPath: geometryOptions.directory).standardizedFileURL
            guard directory.path.caseInsensitiveCompare(outputDir.standardizedFileURL.path) != .orderedSame,
                !FileManager.default.fileExists(atPath: outputDir.appendingPathComponent("index.html").path),
                GalleryGeometryCLIOptions.entryIDs.allSatisfy({
                    !FileManager.default.fileExists(atPath: outputDir.appendingPathComponent("\($0).png").path)
                })
            else { throw GalleryError.geometryDiagnosticsOutputUnavailable }
            let created = directory.path.withCString(encodedAs: UTF16.self) { CreateDirectoryW($0, nil) }
            guard created else { throw GalleryError.geometryDiagnosticsOutputUnavailable }
            geometryOutput = directory
        } else {
            geometryOutput = nil
        }
        try FileManager.default.createDirectory(
            at: outputDir,
            withIntermediateDirectories: true
        )

        let baseSpecs: [GallerySpec] = [
            GallerySpec(
                id: "rectangle", title: "Rectangle",
                view: AnyView(
                    Rectangle().fill(.red).frame(width: 120, height: 80)
                )),
            GallerySpec(
                id: "circle", title: "Circle",
                view: AnyView(
                    Circle().fill(.blue).frame(width: 100, height: 100)
                )),
            GallerySpec(
                id: "rounded-rect", title: "Rounded Rectangle",
                view: AnyView(
                    RoundedRectangle(cornerRadius: 20).fill(.green).frame(width: 120, height: 80)
                )),
            GallerySpec(
                id: "text", title: "Text",
                view: AnyView(
                    Text("Hello").foregroundColor(.white)
                )),
            GallerySpec(
                id: "opacity", title: "Opacity 0.5",
                view: AnyView(
                    Rectangle().fill(.white).frame(width: 100, height: 100).opacity(0.5)
                )),
            GallerySpec(
                id: "corner-radius", title: "Corner Radius",
                view: AnyView(
                    Rectangle().fill(.white).frame(width: 120, height: 120).cornerRadius(30)
                )),
            GallerySpec(
                id: "border", title: "Border",
                view: AnyView(
                    Rectangle().fill(.black).frame(width: 120, height: 120).border(.yellow, width: 4)
                )),
            GallerySpec(
                id: "shadow", title: "Shadow",
                view: AnyView(
                    Rectangle().fill(.white).frame(width: 80, height: 80).shadow(color: .white, radius: 6, x: 4, y: 4)
                )),
            GallerySpec(
                id: "rotation", title: "Rotation 45°",
                view: AnyView(
                    Rectangle().fill(.purple).frame(width: 100, height: 40).rotationEffect(.degrees(45))
                )),
            GallerySpec(
                id: "scale", title: "Scale 1.5x",
                view: AnyView(
                    Rectangle().fill(.yellow).frame(width: 60, height: 60).scaleEffect(x: 1.5, y: 1.5)
                )),
            GallerySpec(
                id: "offset", title: "Offset (20, 10)",
                view: AnyView(
                    Rectangle().fill(.yellow).frame(width: 80, height: 80).offset(x: 20, y: 10)
                )),
            GallerySpec(
                id: "padding", title: "Padding",
                view: AnyView(
                    Rectangle().fill(.white).frame(width: 80, height: 80).padding(20)
                )),
            GallerySpec(
                id: "hstack", title: "HStack",
                view: AnyView(
                    HStack(spacing: 8) {
                        Rectangle().fill(.red).frame(width: 40, height: 40)
                        Rectangle().fill(.green).frame(width: 40, height: 40)
                        Rectangle().fill(.blue).frame(width: 40, height: 40)
                    }
                )),
            GallerySpec(
                id: "vstack", title: "VStack",
                view: AnyView(
                    VStack(spacing: 8) {
                        Rectangle().fill(.red).frame(width: 40, height: 20)
                        Rectangle().fill(.green).frame(width: 40, height: 20)
                        Rectangle().fill(.blue).frame(width: 40, height: 20)
                    }
                )),
            GallerySpec(
                id: "zstack", title: "ZStack",
                view: AnyView(
                    ZStack {
                        Rectangle().fill(.red).frame(width: 100, height: 100)
                        Rectangle().fill(.blue).frame(width: 60, height: 60)
                        Rectangle().fill(.green).frame(width: 30, height: 30)
                    }
                )),
            GallerySpec(
                id: "brightness", title: "Brightness -0.5",
                view: AnyView(
                    Rectangle().fill(.white).frame(width: 100, height: 100).brightness(-0.5)
                )),
            GallerySpec(
                id: "contrast", title: "Contrast 2.0",
                view: AnyView(
                    Rectangle().fill(.gray)
                        .frame(width: 100, height: 100).contrast(2.0)
                )),
            GallerySpec(
                id: "grayscale", title: "Grayscale",
                view: AnyView(
                    Rectangle().fill(.red).frame(width: 100, height: 100).grayscale(1.0)
                )),
            GallerySpec(
                id: "hue-rotation", title: "Hue Rotation 120°",
                view: AnyView(
                    Rectangle().fill(.red).frame(width: 100, height: 100).hueRotation(.degrees(120))
                )),
            GallerySpec(
                id: "color-invert", title: "Color Invert",
                view: AnyView(
                    Rectangle().fill(.red).frame(width: 100, height: 100).colorInvert()
                )),
            GallerySpec(
                id: "blur", title: "Blur",
                view: AnyView(
                    Rectangle().fill(.white).frame(width: 80, height: 80).blur(radius: 4)
                )),
            GallerySpec(
                id: "blend-multiply", title: "Blend Multiply",
                view: AnyView(
                    ZStack {
                        Rectangle().fill(.red).frame(width: 80, height: 80)
                        Rectangle().fill(.blue).frame(width: 80, height: 80).blendMode(.multiply)
                    }
                )),
            GallerySpec(
                id: "blend-screen", title: "Blend Screen",
                view: AnyView(
                    ZStack {
                        Rectangle().fill(.red).frame(width: 80, height: 80)
                        Rectangle().fill(.blue).frame(width: 80, height: 80).blendMode(.screen)
                    }
                )),
            GallerySpec(
                id: "blend-plus", title: "Blend Plus Lighter",
                view: AnyView(
                    ZStack {
                        Rectangle().fill(.green).frame(width: 80, height: 80)
                        Rectangle().fill(.red).frame(width: 80, height: 80).blendMode(.plusLighter)
                    }
                )),
            GallerySpec(
                id: "clip-shape", title: "ClipShape RoundedRect",
                view: AnyView(
                    Rectangle().fill(.white).frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 30))
                )),
            GallerySpec(
                id: "drawing-group", title: "DrawingGroup + Opacity",
                view: AnyView(
                    ZStack {
                        Rectangle().fill(.white).frame(width: 60, height: 60)
                        Rectangle().fill(.white).frame(width: 60, height: 60)
                    }
                    .opacity(0.5)
                    .drawingGroup()
                )),
            // MARK: Controls — buttons
            GallerySpec(
                id: "button", title: "Button",
                view: AnyView(
                    Button("Tap Me") {}
                        .frame(width: 100, height: 40)
                )),
            GallerySpec(
                id: "button-destructive", title: "Button Destructive",
                view: AnyView(
                    Button("Delete", role: .destructive) {}
                        .frame(width: 100, height: 40)
                )),
            GallerySpec(
                id: "button-disabled", title: "Button Disabled",
                view: AnyView(
                    // 140pt matches the other pinned button entries: a push
                    // bezel reserves `MacOSControlMetrics.Button` content
                    // insets, so a 120pt pill truncates this title.
                    Button("Unavailable") {}
                        .disabled(true)
                        .frame(width: 140, height: 40)
                )),
            GallerySpec(
                id: "button-styles", title: "Button Styles",
                view: AnyView(
                    VStack(spacing: 8) {
                        Button("Default") {}
                            .frame(width: 140, height: 32)
                        Button("Prominent") {}
                            .buttonStyle(BorderedProminentButtonStyle())
                            .frame(width: 140, height: 32)
                        Button("Plain") {}
                            .buttonStyle(PlainButtonStyle())
                            .frame(width: 140, height: 32)
                    }
                    .frame(width: 180, height: 140)
                )),
            GallerySpec(
                id: "button-focusable", title: "Button Focusable",
                view: AnyView(
                    Button("Focus Me") {}
                        .focusable(true)
                        .focused(FocusState(wrappedValue: true).projectedValue)
                        .frame(width: 120, height: 40)
                )),

            // MARK: Controls — text input
            GallerySpec(
                id: "text-field", title: "TextField Filled",
                view: AnyView(
                    TextField("Placeholder", text: .constant("Hello"))
                        .frame(width: 160, height: 36)
                        .padding(8)
                )),
            GallerySpec(
                id: "text-field-empty", title: "TextField Empty",
                view: AnyView(
                    TextField("Search", text: .constant(""))
                        .frame(width: 160, height: 36)
                        .padding(8)
                )),
            GallerySpec(
                id: "text-field-disabled", title: "TextField Disabled",
                view: AnyView(
                    TextField("Locked", text: .constant("Read only"))
                        .disabled(true)
                        .frame(width: 160, height: 36)
                        .padding(8)
                )),
            GallerySpec(
                id: "text-field-focused", title: "TextField Focused",
                view: AnyView(
                    TextField("Name", text: .constant("Ada"))
                        .focused(FocusState(wrappedValue: true).projectedValue)
                        .frame(width: 160, height: 36)
                        .padding(8)
                )),
            GallerySpec(
                id: "secure-field", title: "SecureField",
                view: AnyView(
                    SecureField("Password", text: .constant("secret"))
                        .frame(width: 160, height: 36)
                        .padding(8)
                )),
            GallerySpec(
                id: "text-input-stack", title: "Text Input Stack",
                view: AnyView(
                    VStack(spacing: 8) {
                        TextField("Email", text: .constant("a@b.co"))
                            .frame(width: 160, height: 30)
                        SecureField("Password", text: .constant("secret"))
                            .frame(width: 160, height: 30)
                        TextField("Notes", text: .constant(""))
                            .disabled(true)
                            .frame(width: 160, height: 30)
                    }
                    .padding(8)
                    .frame(width: 180, height: 140)
                )),

            // MARK: Controls — toggle / slider / picker / stepper
            GallerySpec(
                id: "toggle", title: "Toggle On",
                view: AnyView(
                    Toggle("Enabled", isOn: .constant(true))
                        .frame(width: 150, height: 36)
                )),
            GallerySpec(
                id: "toggle-off", title: "Toggle Off",
                view: AnyView(
                    Toggle("Disabled Flag", isOn: .constant(false))
                        .frame(width: 160, height: 36)
                )),
            GallerySpec(
                id: "toggle-disabled", title: "Toggle Disabled",
                view: AnyView(
                    Toggle("Locked", isOn: .constant(true))
                        .disabled(true)
                        .frame(width: 150, height: 36)
                )),
            GallerySpec(
                id: "toggle-states", title: "Toggle States",
                view: AnyView(
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Notifications", isOn: .constant(true))
                        Toggle("Sounds", isOn: .constant(false))
                        Toggle("Airplane", isOn: .constant(true))
                            .disabled(true)
                    }
                    .frame(width: 170, height: 140)
                    .padding(8)
                )),
            GallerySpec(
                id: "slider", title: "Slider Mid",
                view: AnyView(
                    Slider(value: .constant(0.5))
                        .frame(width: 160, height: 36)
                )),
            GallerySpec(
                id: "slider-low", title: "Slider Low",
                view: AnyView(
                    Slider(value: .constant(0.15), in: 0...1)
                        .frame(width: 160, height: 36)
                )),
            GallerySpec(
                id: "slider-high", title: "Slider High",
                view: AnyView(
                    Slider(value: .constant(0.9), in: 0...1)
                        .frame(width: 160, height: 36)
                )),
            GallerySpec(
                id: "slider-labeled", title: "Slider Labeled",
                view: AnyView(
                    Slider(value: .constant(0.65), in: 0...1) {
                        Text("Volume")
                    } minimumValueLabel: {
                        Text("0")
                    } maximumValueLabel: {
                        Text("100")
                    }
                    .frame(width: 230, height: 80)
                    .padding(8)
                ),
                size: IntSize(width: 260, height: 140)),
            // The one entry that certifies a segmented picker's *chrome* in
            // both appearances, so its canvas has to be wide enough for the
            // control to lay out at its intrinsic width. At 160pt the three
            // segments and the "Color" caption shared a band narrower than
            // their own titles and the baseline pinned "Gr…" as the correct
            // rendering of "Green" — a truncation the entry's own width
            // caused, certified forever as chrome. The constrained-width
            // behaviour that produced it is real and stays covered by
            // `WinSwiftUIPickerTests` / `ControlChromePolishTests`, where a
            // narrow frame is the thing under test rather than the canvas.
            GallerySpec(
                id: "picker", title: "Picker",
                view: AnyView(
                    Picker("Color", selection: .constant(1)) {
                        Text("Red").tag(0)
                        Text("Green").tag(1)
                        Text("Blue").tag(2)
                    }
                    .frame(width: 240, height: 40)
                ),
                size: IntSize(width: 280, height: 200)),
            GallerySpec(
                id: "picker-theme", title: "Picker Theme",
                view: AnyView(
                    Picker("Theme", selection: .constant(2)) {
                        Text("Light").tag(0)
                        Text("Dark").tag(1)
                        Text("Auto").tag(2)
                    }
                    .frame(width: 160, height: 40)
                )),
            GallerySpec(
                id: "stepper", title: "Stepper",
                view: AnyView(
                    Stepper(value: .constant(5), in: 0...10) {
                        Text("Count: 5")
                    }
                    .frame(width: 150, height: 40)
                )),
            GallerySpec(
                id: "stepper-bounds", title: "Stepper At Max",
                view: AnyView(
                    Stepper(value: .constant(10), in: 0...10) {
                        Text("Count: 10")
                    }
                    .frame(width: 150, height: 40)
                )),

            // MARK: Controls — progress
            GallerySpec(
                id: "progress-view", title: "Progress Determinate",
                view: AnyView(
                    ProgressView(value: 0.6)
                        .frame(width: 140, height: 36)
                )),
            GallerySpec(
                id: "progress-low", title: "Progress Low",
                view: AnyView(
                    ProgressView(value: 0.15)
                        .frame(width: 140, height: 36)
                )),
            GallerySpec(
                id: "progress-complete", title: "Progress Complete",
                view: AnyView(
                    ProgressView(value: 1.0)
                        .frame(width: 140, height: 36)
                )),
            GallerySpec(
                id: "progress-indeterminate", title: "Progress Indeterminate",
                view: AnyView(
                    ProgressView()
                        .frame(width: 80, height: 40)
                )),
            GallerySpec(
                id: "progress-labeled", title: "Progress Labeled",
                view: AnyView(
                    ProgressView("Loading", value: 0.4)
                        .frame(width: 160, height: 50)
                        .padding(8)
                )),
            GallerySpec(
                id: "progress-states", title: "Progress States",
                view: AnyView(
                    VStack(spacing: 12) {
                        ProgressView(value: 0.25)
                            .frame(width: 150, height: 20)
                        ProgressView(value: 0.55)
                            .frame(width: 150, height: 20)
                        ProgressView(value: 0.9)
                            .frame(width: 150, height: 20)
                        ProgressView()
                            .frame(width: 40, height: 20)
                    }
                    .padding(8)
                    .frame(width: 180, height: 140)
                )),

            // MARK: Controls — lists & scrolling
            GallerySpec(
                id: "list", title: "List",
                view: AnyView(
                    List {
                        Text("Inbox")
                        Text("Sent")
                        Text("Archive")
                        Text("Trash")
                    }
                    .frame(width: 160, height: 140)
                )),
            GallerySpec(
                id: "list-foreach", title: "List ForEach",
                view: AnyView(
                    List {
                        ForEach(0..<6, id: \.self) { index in
                            Text("Row \(index + 1)")
                        }
                    }
                    .frame(width: 160, height: 150)
                )),
            GallerySpec(
                id: "list-data", title: "List Data",
                view: AnyView(
                    List(["Alpha", "Beta", "Gamma", "Delta"], id: \.self) { name in
                        Text(name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .listStyle(InsetListStyle(alternatesRowBackgrounds: true))
                    .frame(width: 230, height: 180)
                ),
                size: IntSize(width: 250, height: 200)),
            GallerySpec(
                id: "scroll-view", title: "ScrollView",
                view: AnyView(
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(0..<8, id: \.self) { index in
                                Text("Scroll row \(index + 1)")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(
                                                index % 2 == 0
                                                    ? Color(red: 0.18, green: 0.22, blue: 0.30, alpha: 1)
                                                    : Color(red: 0.12, green: 0.15, blue: 0.20, alpha: 1)
                                            )
                                    )
                            }
                        }
                        .padding(6)
                    }
                    .frame(width: 170, height: 150)
                )),
            GallerySpec(
                id: "scroll-view-shapes", title: "ScrollView Shapes",
                view: AnyView(
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(0..<5, id: \.self) { index in
                                Rectangle()
                                    .fill(index % 2 == 0 ? .red : .blue)
                                    .frame(width: 140, height: 28)
                            }
                        }
                    }
                    .frame(width: 160, height: 100)
                )),

            // MARK: Controls — form / navigation / composite
            GallerySpec(
                id: "form", title: "Form",
                view: AnyView(
                    Form {
                        Section("Account") {
                            TextField("Name", text: .constant("Ada"))
                            Toggle("Active", isOn: .constant(true))
                        }
                        Section("Prefs") {
                            Slider(value: .constant(0.4))
                        }
                    }
                    // A grouped section header is a 15/600 heading now, and a
                    // form row states its own height, so the fixture frame
                    // grew with the design rather than clipping its last row.
                    .frame(width: 170, height: 210)
                ),
                size: IntSize(width: 200, height: 230)),
            GallerySpec(
                id: "form-settings", title: "Form Settings",
                view: AnyView(
                    Form {
                        TextField("User", text: .constant("admin"))
                        SecureField("Pass", text: .constant("secret"))
                        Toggle("Dark Mode", isOn: .constant(true))
                        Picker("Theme", selection: .constant(1)) {
                            Text("Light").tag(0)
                            Text("Dark").tag(1)
                        }
                        Button("Save") {}
                    }
                    .formStyle(GroupedFormStyle())
                    .frame(width: 240, height: 250)
                ),
                size: IntSize(width: 260, height: 270)),
            GallerySpec(
                id: "navigation-stack", title: "NavigationStack",
                view: AnyView(
                    NavigationStack {
                        Text("Root View")
                            .navigationTitle("Home")
                    }
                    .frame(width: 160, height: 120)
                )),
            GallerySpec(
                id: "controls-panel", title: "Controls Panel",
                view: AnyView(
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Panel")
                            .foregroundColor(.white)
                        TextField("Query", text: .constant("swiftui"))
                            .frame(height: 28)
                        HStack(spacing: 8) {
                            Toggle("On", isOn: .constant(true))
                            Toggle("Off", isOn: .constant(false))
                        }
                        Slider(value: .constant(0.55))
                            .frame(height: 24)
                        ProgressView(value: 0.7)
                            .frame(height: 16)
                        HStack(spacing: 8) {
                            Button("OK") {}
                                .frame(width: 56, height: 28)
                            Button("Cancel", role: .cancel) {}
                                .frame(width: 84, height: 28)
                            Button("Delete", role: .destructive) {}
                                .disabled(true)
                                .frame(width: 84, height: 28)
                        }
                    }
                    .padding(10)
                    .frame(width: 260, height: 210)
                ),
                size: IntSize(width: 280, height: 230)),
            GallerySpec(
                id: "focus-ring", title: "Focus Ring Pair",
                view: AnyView(
                    VStack(spacing: 10) {
                        TextField("Focused", text: .constant("Active"))
                            .focused(FocusState(wrappedValue: true).projectedValue)
                            .frame(width: 150, height: 32)
                        TextField("Blurred", text: .constant("Idle"))
                            .focused(FocusState(wrappedValue: false).projectedValue)
                            .frame(width: 150, height: 32)
                        Button("Submit") {}
                            .focusable(true)
                            .frame(width: 100, height: 32)
                    }
                    .padding(8)
                    .frame(width: 180, height: 150)
                )),
            GallerySpec(
                id: "aspect-ratio", title: "Aspect Ratio",
                view: AnyView(
                    Rectangle()
                        .fill(.red)
                        .aspectRatio(2.0, contentMode: .fit)
                        .frame(width: 160, height: 100)
                )),
            GallerySpec(
                id: "mask", title: "Mask",
                view: AnyView(
                    Rectangle()
                        .fill(.blue)
                        .frame(width: 120, height: 120)
                        .mask(
                            Circle()
                                .frame(width: 100, height: 100)
                        )
                )),
            GallerySpec(
                id: "overlay", title: "Overlay",
                view: AnyView(
                    Rectangle()
                        .fill(.green)
                        .frame(width: 100, height: 100)
                        .overlay(
                            Circle().fill(.white).frame(width: 40, height: 40),
                            alignment: .topTrailing
                        )
                )),
            GallerySpec(
                id: "background-alignment", title: "Background + Alignment",
                view: AnyView(
                    Text("A")
                        .frame(width: 60, height: 60)
                        .background(
                            Circle().fill(.red),
                            alignment: .center
                        )
                )),
            GallerySpec(
                id: "matched-geometry", title: "MatchedGeometryEffect",
                view: AnyView(
                    HStack(spacing: 20) {
                        Rectangle()
                            .fill(.blue)
                            .frame(width: 40, height: 40)
                            .matchedGeometryEffect(id: "shape", in: Namespace().wrappedValue)
                        Rectangle()
                            .fill(.blue)
                            .frame(width: 60, height: 60)
                            .matchedGeometryEffect(id: "shape2", in: Namespace().wrappedValue)
                    }
                )),
            GallerySpec(
                id: "menu", title: "Menu",
                view: AnyView(
                    Menu("Options") {
                        Button("Option 1") {}
                        Button("Option 2") {}
                    }
                    .frame(width: 120, height: 40)
                )),
            GallerySpec(
                id: "link", title: "Link",
                view: AnyView(
                    Link("Open", destination: URL(string: "https://example.com")!)
                        .frame(width: 100, height: 40)
                )),
            GallerySpec(
                id: "divider", title: "Divider",
                view: AnyView(
                    VStack {
                        Text("Above")
                        Divider()
                        Text("Below")
                    }
                    .frame(width: 120, height: 80)
                )),
            GallerySpec(
                id: "spacer", title: "Spacer",
                view: AnyView(
                    HStack {
                        Rectangle().fill(.red).frame(width: 30, height: 30)
                        Spacer()
                        Rectangle().fill(.blue).frame(width: 30, height: 30)
                    }
                    .frame(width: 160, height: 40)
                )),
            GallerySpec(
                id: "geometry-reader", title: "GeometryReader",
                view: AnyView(
                    GeometryReader { proxy in
                        Text("\(Int(proxy.size.width))x\(Int(proxy.size.height))")
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                    .frame(width: 120, height: 80)
                )),
            GallerySpec(
                id: "for-each", title: "ForEach",
                view: AnyView(
                    VStack(spacing: 4) {
                        ForEach(0..<4, id: \.self) { index in
                            Rectangle()
                                .fill(index % 2 == 0 ? .green : .yellow)
                                .frame(width: 140, height: 20)
                        }
                    }
                )),
            GallerySpec(
                id: "if-else", title: "Conditional View",
                view: AnyView(
                    VStack(spacing: 8) {
                        if true {
                            Rectangle().fill(.red).frame(width: 80, height: 30)
                        } else {
                            Rectangle().fill(.blue).frame(width: 80, height: 30)
                        }
                    }
                )),
            GallerySpec(
                id: "group", title: "Group",
                view: AnyView(
                    Group {
                        Rectangle().fill(.red).frame(width: 60, height: 30)
                        Rectangle().fill(.green).frame(width: 60, height: 30)
                        Rectangle().fill(.blue).frame(width: 60, height: 30)
                    }
                )),
            GallerySpec(
                id: "transition", title: "Transition",
                view: AnyView(
                    Text("Hello")
                        .transition(.opacity)
                        .frame(width: 80, height: 40)
                )),
            GallerySpec(
                id: "animation", title: "Animation",
                view: AnyView(
                    Rectangle()
                        .fill(.red)
                        .frame(width: 80, height: 80)
                        .animation(.easeInOut, value: 1)
                )),
            GallerySpec(
                id: "canvas-fill-color", title: "Canvas (color fill)",
                view: AnyView(
                    Canvas { ctx, size in
                        var path = Path()
                        path.moveTo(Point(x: size.width / 2, y: 10))
                        path.lineTo(Point(x: size.width - 10, y: size.height - 10))
                        path.lineTo(Point(x: 10, y: size.height - 10))
                        path.close()
                        ctx.fill(path, with: .color(Color(red: 0.95, green: 0.55, blue: 0.20, alpha: 1)))
                    }
                    .frame(width: 160, height: 140)
                )),
            GallerySpec(
                id: "canvas-stroke", title: "Canvas (stroke)",
                view: AnyView(
                    Canvas { ctx, size in
                        var path = Path()
                        path.moveTo(Point(x: 10, y: size.height / 2))
                        let step = (size.width - 20) / 10
                        for index in 1...10 {
                            let x = 10 + Double(index) * step
                            let y = size.height / 2 + (index % 2 == 0 ? -30.0 : 30.0)
                            path.lineTo(Point(x: x, y: y))
                        }
                        ctx.stroke(
                            path,
                            with: .color(Color(red: 0.42, green: 0.78, blue: 0.92, alpha: 1)),
                            lineWidth: 3
                        )
                    }
                    .frame(width: 160, height: 140)
                )),
            GallerySpec(
                id: "canvas-gradient", title: "Canvas (gradient)",
                view: AnyView(
                    Canvas { ctx, size in
                        ctx.fill(
                            Rect(x: 10, y: 10, width: size.width - 20, height: size.height - 20),
                            with: .linearGradient(
                                Gradient(colors: [
                                    Color(red: 0.20, green: 0.30, blue: 0.95, alpha: 1),
                                    Color(red: 0.80, green: 0.40, blue: 0.55, alpha: 1),
                                ]),
                                startPoint: CGPoint(x: 10, y: 10),
                                endPoint: CGPoint(x: size.width - 10, y: size.height - 10)
                            )
                        )
                    }
                    .frame(width: 160, height: 140)
                )),
            GallerySpec(
                id: "canvas-path-gradient", title: "Canvas (gradient path)",
                view: AnyView(
                    Canvas { ctx, size in
                        let bounds = Rect(
                            x: 14, y: 16, width: size.width - 28, height: size.height - 32)
                        let path = Path(ellipseIn: bounds)
                        let fillGradient = Gradient(stops: [
                            .init(color: Color(red: 0.32, green: 0.24, blue: 0.92, alpha: 1), location: 0),
                            .init(color: Color(red: 0.16, green: 0.82, blue: 0.84, alpha: 1), location: 0.42),
                            .init(color: Color(red: 0.96, green: 0.42, blue: 0.58, alpha: 1), location: 1),
                        ])
                        ctx.fill(
                            path,
                            with: .linearGradient(
                                fillGradient,
                                startPoint: CGPoint(x: bounds.minX + 12, y: bounds.minY + 8),
                                endPoint: CGPoint(x: bounds.maxX - 12, y: bounds.maxY - 8)
                            )
                        )
                        ctx.stroke(
                            path,
                            with: .linearGradient(
                                Gradient(colors: [
                                    Color(red: 1, green: 1, blue: 1, alpha: 0.9),
                                    Color(red: 0.32, green: 0.86, blue: 1, alpha: 0.65),
                                ]),
                                startPoint: CGPoint(x: bounds.minX, y: bounds.minY),
                                endPoint: CGPoint(x: bounds.minX, y: bounds.maxY)
                            ),
                            lineWidth: 3
                        )
                    }
                    .frame(width: 160, height: 140)
                )),
            GallerySpec(
                id: "canvas-transform", title: "Canvas (transform)",
                view: AnyView(
                    Canvas { ctx, size in
                        let cx = size.width / 2
                        let cy = size.height / 2
                        for index in 0..<8 {
                            ctx.drawLayer { sub in
                                sub.translateBy(x: cx, y: cy)
                                sub.rotate(by: .degrees(Double(index) * 45))
                                sub.opacity = 1.0 - Double(index) * 0.08
                                sub.fill(
                                    Rect(x: -10, y: -45, width: 20, height: 30),
                                    with: .color(Color(red: 0.95, green: 0.55, blue: 0.20, alpha: 1))
                                )
                            }
                        }
                    }
                    .frame(width: 160, height: 140)
                )),

            // MARK: Showcase — typography, symbols, and component composition

            GallerySpec(
                id: "typography-scale", title: "Typography Scale",
                view: AnyView(
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Design system")
                            .font(.largeTitle.weight(.semibold))
                        Text("A complete type hierarchy")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Divider()
                        Text("Headline · Information that matters")
                            .font(.headline)
                        Text("Body · Every detail, beautifully clear.")
                            .font(.body)
                        Text("CAPTION · UPDATED JUST NOW")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(18)
                    .frame(width: 300, height: 216, alignment: .leading)
                ),
                size: IntSize(width: 320, height: 240)),
            GallerySpec(
                id: "semantic-labels", title: "Labels and Symbol Styles",
                view: AnyView(
                    VStack(alignment: .leading, spacing: 15) {
                        Label("Project overview", systemImage: "square.grid.2x2")
                            .font(.headline)
                            .foregroundColor(.blue)
                        Label("Shared with your team", systemImage: "person")
                            .foregroundColor(.secondary)
                        Label("Notifications enabled", systemImage: "bell")
                        Label("Synced and ready", systemImage: "checkmark.circle")
                            .foregroundColor(.green)
                        HStack(spacing: 18) {
                            Label("Settings", systemImage: "gearshape")
                                .labelStyle(IconOnlyLabelStyle())
                            Label("Documents", systemImage: "doc.text")
                                .labelStyle(TitleOnlyLabelStyle())
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding(20)
                    .frame(width: 280, height: 196, alignment: .leading)
                ),
                size: IntSize(width: 300, height: 220)),
            GallerySpec(
                id: "symbol-palette", title: "Individually Tinted Symbols",
                view: AnyView(
                    VStack(alignment: .leading, spacing: 18) {
                        Text("SYMBOL LIBRARY")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        HStack(spacing: 22) {
                            Image(systemName: "sparkles")
                                .foregroundColor(.purple)
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.orange)
                            Image(systemName: "heart.fill")
                                .foregroundColor(.pink)
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                        }
                        .font(.title2)
                        HStack(spacing: 22) {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.blue)
                            Image(systemName: "chart.bar")
                                .foregroundColor(.mint)
                            Image(systemName: "globe")
                                .foregroundColor(.cyan)
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.green)
                        }
                        .font(.title2)
                        Text("Eight crisp, independently colored glyphs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(22)
                    .frame(width: 290, height: 204, alignment: .leading)
                ),
                size: IntSize(width: 320, height: 240)),
            GallerySpec(
                id: "bitmap-cap-insets", title: "Bitmap Fixed Cap Insets",
                view: AnyView(DemoBitmapResizingSample(.cappedStretch).padding(16)),
                size: IntSize(width: 128, height: 128)),
            GallerySpec(
                id: "bitmap-tile", title: "Bitmap Repeating Tiles",
                view: AnyView(DemoBitmapResizingSample(.tile).padding(16)),
                size: IntSize(width: 128, height: 128)),
            GallerySpec(
                id: "bitmap-aspect-fit", title: "Capped Bitmap Aspect Fit",
                view: AnyView(DemoBitmapResizingSample(.aspectFit).padding(16)),
                size: IntSize(width: 128, height: 128)),
            GallerySpec(
                id: "status-badges", title: "Semantic Status Badges",
                view: AnyView(
                    VStack(alignment: .leading, spacing: 15) {
                        Text("DEPLOYMENT STATUS")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        HStack(spacing: 10) {
                            Label("Healthy", systemImage: "checkmark.circle")
                                .foregroundColor(.green)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.16), in: Capsule())
                            Label("Building", systemImage: "bolt.fill")
                                .foregroundColor(.orange)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.orange.opacity(0.16), in: Capsule())
                        }
                        .font(.caption.weight(.semibold))
                        HStack(spacing: 10) {
                            Label("Preview", systemImage: "sparkles")
                                .foregroundColor(.purple)
                            Label("Offline", systemImage: "xmark.circle")
                                .foregroundColor(.secondary)
                        }
                        .font(.footnote)
                    }
                    .padding(20)
                    .frame(width: 310, height: 164, alignment: .leading)
                ),
                size: IntSize(width: 340, height: 200)),
            GallerySpec(
                id: "button-control-sizes", title: "Button Control Sizes",
                view: AnyView(
                    VStack(alignment: .leading, spacing: 12) {
                        Text("CONTROL SIZES")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        HStack(spacing: 12) {
                            Button("Mini") {}
                                .controlSize(.mini)
                                .frame(width: 64, height: 24)
                            Button("Small") {}
                                .controlSize(.small)
                                .frame(width: 74, height: 28)
                        }
                        HStack(spacing: 12) {
                            Button("Regular") {}
                                .controlSize(.regular)
                                .frame(width: 94, height: 32)
                            Button("Large") {}
                                .controlSize(.large)
                                .frame(width: 96, height: 38)
                        }
                        Button("Primary action") {}
                            .buttonStyle(BorderedProminentButtonStyle())
                            .controlSize(.large)
                            .frame(width: 168, height: 40)
                    }
                    .padding(18)
                    .frame(width: 292, height: 206, alignment: .leading)
                ),
                size: IntSize(width: 320, height: 230)),
            GallerySpec(
                id: "tinted-controls", title: "Tinted Control Families",
                view: AnyView(
                    VStack(alignment: .leading, spacing: 15) {
                        Text("ACCENT COLORS")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        Toggle("Ocean", isOn: .constant(true))
                            .tint(.cyan)
                        Slider(value: .constant(0.72), in: 0...1)
                            .tint(.purple)
                        ProgressView(value: 0.58)
                            .tint(.mint)
                        Button("Continue") {}
                            .buttonStyle(BorderedProminentButtonStyle())
                            .tint(.indigo)
                            .frame(width: 132, height: 34)
                    }
                    .padding(20)
                    .frame(width: 286, height: 214, alignment: .leading)
                ),
                size: IntSize(width: 320, height: 250)),
            GallerySpec(
                id: "group-box", title: "Grouped Settings Card",
                view: AnyView(
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledContent("Region", value: "US East")
                            LabeledContent("Environment", value: "Production")
                            Divider()
                            Toggle("Auto deploy", isOn: .constant(true))
                        }
                    } label: {
                        Label("Deployment", systemImage: "bolt.fill")
                            .font(.headline)
                    }
                    .frame(width: 284, height: 192)
                    .padding(12)
                ),
                size: IntSize(width: 320, height: 240)),
            GallerySpec(
                id: "disclosure-collapsed", title: "Disclosure Group · Collapsed",
                view: AnyView(
                    VStack(alignment: .leading, spacing: 10) {
                        Text("CONFIGURATION")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        DisclosureGroup("Advanced options", isExpanded: .constant(false)) {
                            Toggle("Verbose logging", isOn: .constant(false))
                        }
                        Divider()
                        Label("Default settings applied", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .frame(width: 290, height: 148, alignment: .leading)
                ),
                size: IntSize(width: 320, height: 180)),
            GallerySpec(
                id: "disclosure-expanded", title: "Disclosure Group · Expanded",
                view: AnyView(
                    VStack(alignment: .leading, spacing: 10) {
                        Text("CONFIGURATION")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        DisclosureGroup("Advanced options", isExpanded: .constant(true)) {
                            VStack(alignment: .leading, spacing: 10) {
                                Toggle("Verbose logging", isOn: .constant(true))
                                LabeledContent("Retries", value: "3 attempts")
                                ProgressView(value: 0.72)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(16)
                    .frame(width: 290, height: 194, alignment: .leading)
                ),
                size: IntSize(width: 320, height: 230)),
            GallerySpec(
                id: "labeled-content", title: "Key–Value Information Rows",
                view: AnyView(
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Release details", systemImage: "doc.text")
                            .font(.headline)
                        Divider()
                        LabeledContent("Version", value: "2.4.1")
                        LabeledContent("Build", value: "8,420")
                        LabeledContent("Platform") {
                            Label("Windows", systemImage: "square.grid.2x2")
                                .foregroundColor(.blue)
                        }
                        LabeledContent("Status") {
                            Text("Ready")
                                .foregroundColor(.green)
                        }
                    }
                    .padding(18)
                    .frame(width: 306, height: 198, alignment: .leading)
                ),
                size: IntSize(width: 340, height: 230)),
            GallerySpec(
                id: "content-unavailable", title: "Empty State with Action",
                view: AnyView(
                    ContentUnavailableView {
                        Label("No results found", systemImage: "magnifyingglass")
                            .font(.title3.weight(.semibold))
                    } description: {
                        Text("Try a different keyword or clear your filters.")
                            .multilineTextAlignment(.center)
                    } actions: {
                        Button("Clear filters") {}
                            .buttonStyle(BorderedProminentButtonStyle())
                            .frame(width: 126, height: 32)
                    }
                    .frame(width: 308, height: 224)
                ),
                size: IntSize(width: 340, height: 260)),
            GallerySpec(
                id: "dashboard-metrics", title: "Live Metrics Dashboard",
                view: AnyView(
                    GroupBox {
                        HStack(alignment: .top, spacing: 18) {
                            Gauge(value: 0.68, in: 0...1) {
                                Text("Compute")
                            } currentValueLabel: {
                                Text("68%")
                            }
                            .gaugeStyle(AccessoryCircularCapacityGaugeStyle())
                            .tint(.blue)
                            .frame(width: 84, height: 94)
                            Gauge(value: 0.42, in: 0...1) {
                                Text("Memory")
                            } currentValueLabel: {
                                Text("42%")
                            }
                            .gaugeStyle(CircularGaugeStyle())
                            .tint(.mint)
                            .frame(width: 84, height: 94)
                        }
                        Divider()
                        Gauge("Storage", value: 0.73, in: 0...1)
                            .gaugeStyle(LinearCapacityGaugeStyle())
                            .tint(.purple)
                    } label: {
                        Label("System health", systemImage: "waveform.path.ecg")
                            .font(.headline)
                    }
                    .frame(width: 322, height: 226)
                    .padding(10)
                ),
                size: IntSize(width: 360, height: 260)),
            GallerySpec(
                id: "grid-layout", title: "Adaptive Metric Grid",
                view: AnyView(
                    VStack(alignment: .leading, spacing: 12) {
                        Text("WORKSPACE OVERVIEW")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                            GridRow {
                                GroupBox("Projects") {
                                    Text("12")
                                        .font(.title2.weight(.semibold))
                                        .foregroundColor(.blue)
                                }
                                .frame(width: 132, height: 78)
                                GroupBox("Members") {
                                    Text("48")
                                        .font(.title2.weight(.semibold))
                                        .foregroundColor(.purple)
                                }
                                .frame(width: 132, height: 78)
                            }
                            GridRow {
                                GroupBox("Uptime") {
                                    Text("99.9%")
                                        .font(.headline)
                                        .foregroundColor(.green)
                                }
                                .frame(width: 132, height: 78)
                                GroupBox("Regions") {
                                    Text("3")
                                        .font(.title2.weight(.semibold))
                                        .foregroundColor(.orange)
                                }
                                .frame(width: 132, height: 78)
                            }
                        }
                    }
                    .padding(14)
                    .frame(width: 310, height: 214, alignment: .leading)
                ),
                size: IntSize(width: 340, height: 240)),
            GallerySpec(
                id: "tab-view", title: "Tabbed Workspace",
                view: AnyView(
                    TabView(selection: .constant(0)) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Overview", systemImage: "chart.bar")
                                .font(.headline)
                            Text("Your workspace is healthy and up to date.")
                                .font(.body)
                                .foregroundColor(.secondary)
                            ProgressView("Weekly goal", value: 0.76)
                            Button("View report") {}
                                .buttonStyle(BorderedProminentButtonStyle())
                                .frame(width: 124, height: 32)
                        }
                        .padding(16)
                        .tabItem {
                            Label("Overview", systemImage: "house")
                        }
                        .tag(0)
                        Text("Recent activity")
                            .tabItem {
                                Label("Activity", systemImage: "waveform.path.ecg")
                            }
                            .tag(1)
                        Text("Workspace settings")
                            .tabItem {
                                Label("Settings", systemImage: "gearshape")
                            }
                            .tag(2)
                    }
                    .frame(width: 332, height: 220)
                ),
                size: IntSize(width: 360, height: 250)),
            GallerySpec(
                id: "canvas-sparkline", title: "Canvas · Gradient Area Chart",
                view: AnyView(
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("REQUESTS")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                Text("24,680")
                                    .font(.title2.weight(.semibold))
                            }
                            Spacer()
                            Text("+18.4%")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.green)
                        }
                        Canvas { context, size in
                            let samples: [Double] = [0.38, 0.43, 0.36, 0.58, 0.51, 0.73, 0.64, 0.88]
                            let horizontalStep = size.width / Double(samples.count - 1)
                            let chartBottom = size.height - 4
                            var line = Path()
                            var area = Path()
                            for (index, value) in samples.enumerated() {
                                let point = Point(
                                    x: Double(index) * horizontalStep,
                                    y: chartBottom - value * (size.height - 12)
                                )
                                if index == 0 {
                                    line.moveTo(point)
                                    area.moveTo(Point(x: 0, y: chartBottom))
                                    area.lineTo(point)
                                } else {
                                    line.lineTo(point)
                                    area.lineTo(point)
                                }
                            }
                            area.lineTo(Point(x: size.width, y: chartBottom))
                            area.close()
                            context.fill(
                                area,
                                with: .linearGradient(
                                    Gradient(colors: [Color.blue.opacity(0.36), Color.blue.opacity(0.03)]),
                                    startPoint: CGPoint(x: 0, y: 6),
                                    endPoint: CGPoint(x: 0, y: chartBottom)
                                )
                            )
                            context.stroke(
                                line,
                                with: .color(.cyan),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                            )
                            let latest = Point(x: size.width - 4, y: chartBottom - 0.88 * (size.height - 12))
                            context.fill(
                                Path(ellipseIn: Rect(x: latest.x - 4, y: latest.y - 4, width: 8, height: 8)),
                                with: .color(.cyan)
                            )
                        }
                        .frame(width: 292, height: 110)
                    }
                    .padding(16)
                    .frame(width: 324, height: 198, alignment: .leading)
                ),
                size: IntSize(width: 340, height: 220)),
            GallerySpec(
                id: "canvas-donut", title: "Canvas · Segmented Donut Chart",
                view: AnyView(
                    HStack(spacing: 18) {
                        ZStack {
                            Canvas { context, size in
                                let center = Point(x: size.width / 2, y: size.height / 2)
                                let radius = min(size.width, size.height) / 2 - 12
                                let ring = Path(
                                    ellipseIn: Rect(
                                        x: center.x - radius,
                                        y: center.y - radius,
                                        width: radius * 2,
                                        height: radius * 2
                                    )
                                )
                                context.stroke(
                                    ring,
                                    with: .color(Color.white.opacity(0.10)),
                                    style: StrokeStyle(lineWidth: 12)
                                )

                                let segments: [(Double, Double, Color)] = [
                                    (-Double.pi / 2, -Double.pi / 2 + Double.pi * 1.04, .blue),
                                    (-Double.pi / 2 + Double.pi * 1.10, Double.pi * 1.10, .mint),
                                    (Double.pi * 1.16, Double.pi * 1.42, .purple),
                                ]
                                for (startAngle, endAngle, color) in segments {
                                    var segment = Path()
                                    segment.arc(
                                        center: center,
                                        radius: radius,
                                        startAngle: startAngle,
                                        endAngle: endAngle
                                    )
                                    context.stroke(
                                        segment,
                                        with: .color(color),
                                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                                    )
                                }
                            }
                            .frame(width: 138, height: 138)
                            VStack(spacing: 3) {
                                Text("84%")
                                    .font(.title2.weight(.semibold))
                                Text("capacity")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Compute", systemImage: "bolt.fill")
                                .foregroundColor(.blue)
                            Label("Storage", systemImage: "folder.fill")
                                .foregroundColor(.mint)
                            Label("Network", systemImage: "globe")
                                .foregroundColor(.purple)
                        }
                        .font(.caption)
                    }
                    .padding(14)
                    .frame(width: 302, height: 200)
                ),
                size: IntSize(width: 320, height: 240)),

            // MARK: Interaction states
            //
            // One control per family, its ramp walked idle → hover → pressed →
            // focused → disabled. Every entry lays the control out at the
            // canvas origin with a known frame, so the pointer point below is
            // the control's own centre; the render loop refuses to write an
            // entry whose driven state did not change a pixel, so a point that
            // drifts off its control fails the build instead of quietly
            // baselining an idle render.
        ]
        let fileBrowserFixtures = fileBrowserGallerySpecs(entryFilter: entryFilter)
        defer { for model in fileBrowserFixtures.models { model.close() } }
        let darkSpecs = baseSpecs + fileBrowserFixtures.specs + interactionStateSpecs()
        let gallerySpecs = try darkSpecs + lightAppearanceSpecs(from: darkSpecs)

        var entries: [GalleryEntry] = []
        let displayScale = 1.0
        var geometryDiagnosticFailed = false

        for spec in gallerySpecs {
            if let entryFilter, !entryFilter.contains(spec.id) {
                continue
            }
            try await spec.prepare?()
            let fontSession: NativeBitmapFontAttributionSession?
            if fontAttributionOutput != nil, let fixture = NativeBitmapFontFixture(rawValue: spec.id) {
                fontSession = NativeBitmapFontAttributionSession(
                    fixture: fixture, version: bitmapFontAttributionVersion)
            } else {
                fontSession = nil
            }
            defer { fontSession?.close() }
            let snapshot: WinSwiftUIRenderSnapshot
            if geometryOptions != nil {
                guard spec.interaction == nil, spec.size.width == 320, spec.size.height == 240,
                    spec.colorScheme == .dark, displayScale == 1
                else { throw GalleryError.invalidGeometryDiagnostics }
                snapshot = WinSwiftUIRendererSnapshotter.snapshot(
                    of: spec.view, size: spec.size, displayScale: displayScale, colorScheme: spec.colorScheme,
                    clearColor: galleryClearColor(for: spec.colorScheme), timestamp: 0, geometryDiagnostics: true
                )
            } else if let fontSession {
                snapshot = WinSwiftUIRendererSnapshotter.snapshot(
                    of: spec.view, size: spec.size, displayScale: displayScale, colorScheme: spec.colorScheme,
                    clearColor: galleryClearColor(for: spec.colorScheme), bitmapFontAttribution: fontSession
                )
            } else {
                snapshot = WinSwiftUIRendererSnapshotter.snapshot(
                    of: spec.view, size: spec.size, displayScale: displayScale, colorScheme: spec.colorScheme,
                    clearColor: galleryClearColor(for: spec.colorScheme)
                )
            }

            let scene: GPUIScene
            if let interaction = spec.interaction {
                // The idle scene is captured first, for the guard below.
                let idleBitmap = GPUIRawSceneRasterizer.rasterize(snapshot.scene, size: snapshot.size)
                applyInteraction(interaction, to: snapshot.runtime)
                scene = snapshot.runtime.renderScene(at: gallerySettledTimestamp)
                let statefulBitmap = GPUIRawSceneRasterizer.rasterize(scene, size: snapshot.size)
                // A state entry that renders identically to its own idle render
                // is not a state entry — it is an idle render with a misleading
                // name, and it would sit in the gate forever certifying a ramp
                // it never exercised. The usual cause is a pointer point that
                // misses the control, which is silent otherwise.
                guard idleBitmap.pixels != statefulBitmap.pixels else {
                    throw GalleryError.interactionHadNoEffect(
                        id: spec.id, state: interaction.describedState)
                }
            } else {
                scene = snapshot.scene
            }

            let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: snapshot.size)
            let filename = "\(spec.id).png"
            let url = outputDir.appendingPathComponent(filename)
            try bitmap.writePNG(to: url)
            if let geometryOptions, let geometryOutput, let geometryOverrideState {
                do {
                    let sidecar = try GalleryGeometryDiagnosticWriter.encode(
                        diagnostic: snapshot.sceneGeometryDiagnostic, scene: scene,
                        fixtureID: spec.id, invocationID: geometryOptions.invocationID,
                        overrideState: geometryOverrideState, pngFileName: filename,
                        size: snapshot.size, displayScale: displayScale,
                        appearance: spec.colorScheme == .dark ? "dark" : "light"
                    )
                    try sidecar.data.write(
                        to: geometryOutput.appendingPathComponent("\(spec.id).geometry.json"),
                        options: .withoutOverwriting
                    )
                    geometryDiagnosticFailed = geometryDiagnosticFailed || !sidecar.isComplete
                } catch {
                    geometryDiagnosticFailed = true
                    FileHandle.standardError.write(
                        Data("Geometry diagnostic sidecar unavailable; PNG retained.\n".utf8))
                }
            }
            if let fontSession, let fontAttributionOutput, let bitmapFontAttributionInvocation {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let destination = fontAttributionOutput.appendingPathComponent(
                    "\(spec.id).native-font-attribution.json")
                do {
                    let data: Data
                    if bitmapFontAttributionVersion == .v2 {
                        guard let report = fontSession.finishV2(scene: scene) else {
                            throw GalleryError.bitmapFontAttributionOutputUnavailable
                        }
                        data = try encoder.encode(
                            GalleryBitmapFontAttributionEnvelopeV2(
                                invocationID: bitmapFontAttributionInvocation, fixtureID: spec.id,
                                pngFileName: filename, status: report.status, runtime: .current, report: report))
                    } else {
                        let report = fontSession.finish(scene: scene)
                        data = try encoder.encode(
                            GalleryBitmapFontAttributionEnvelope(
                                invocationID: bitmapFontAttributionInvocation, fixtureID: spec.id,
                                pngFileName: filename, status: report.status, runtime: .current, report: report))
                    }
                    guard data.count <= 512 * 1024 else { throw GalleryError.bitmapFontAttributionOutputUnavailable }
                    try data.write(to: destination, options: .withoutOverwriting)
                } catch {
                    // Do not echo a filesystem error containing a user path.
                    // Attribution is supplementary: keep this PNG and render
                    // later fixtures. The collector reports a missing sidecar.
                    FileHandle.standardError.write(
                        Data("Bitmap font attribution sidecar unavailable; native PNG retained.\n".utf8))
                }
            }

            entries.append(
                GalleryEntry(
                    id: spec.id,
                    title: spec.title,
                    filename: filename,
                    size: spec.size,
                    colorScheme: spec.colorScheme,
                    primitiveCount: scene.primitiveCount,
                    layerCount: scene.layers.count
                ))
            print("Rendered \(spec.id)")
        }

        let indexURL = outputDir.appendingPathComponent("index.html")
        try writeGalleryHTML(entries: entries, to: indexURL)
        print("Gallery=\(indexURL.path)")
        print("Entries=\(entries.count)")
        if geometryDiagnosticFailed { throw GalleryError.geometryDiagnosticsIncomplete }
    }
}

// MARK: - Opt-in geometry diagnostics

package struct GalleryGeometryCLIOptions: Sendable {
    package static let entryIDs: Set<String> = ["typography-scale", "canvas-donut"]
    package let directory: String
    package let invocationID: String

    package static func validate(
        directory: String?, invocationID: String?, rawEntries: [String]?,
        entryArgumentCount: Int, bitmapArgumentsPresent: Bool
    ) throws -> GalleryGeometryCLIOptions? {
        guard directory != nil || invocationID != nil else { return nil }
        guard let directory, !directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let invocationID, invocationID.utf8.count == 32,
            invocationID.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
            let rawEntries, entryArgumentCount == 1, rawEntries.count == 2,
            Set(rawEntries) == entryIDs, !bitmapArgumentsPresent
        else { throw GalleryError.invalidGeometryDiagnostics }
        return GalleryGeometryCLIOptions(directory: directory, invocationID: invocationID)
    }
}

package struct GalleryGeometryEncodedSidecar {
    package let data: Data
    package let isComplete: Bool
}

@MainActor
package enum GalleryGeometryDiagnosticWriter {
    package static func encode(
        diagnostic: RetainedSceneGeometryDiagnostic?, scene: GPUIScene,
        fixtureID: String, invocationID: String, overrideState: String,
        pngFileName: String, size: IntSize, displayScale: Double, appearance: String
    ) throws -> GalleryGeometryEncodedSidecar {
        var issues: [String] = []
        if !GalleryGeometryCLIOptions.entryIDs.contains(fixtureID) {
            issues.append("unexpected-fixture")
        }
        if size.width != 320 || size.height != 240 || displayScale != 1 || appearance != "dark" {
            issues.append("unexpected-render-configuration")
        }
        if overrideState != "absent" && overrideState != "1" {
            issues.append("mode-key-state-unavailable")
        }

        let reportedNodes = diagnostic?.nodes ?? []
        let nodes = reportedNodes.count <= RetainedSceneGeometryLimits.maxNodes ? reportedNodes : []
        if nodes.count != reportedNodes.count { issues.append("node-count-limit") }
        if nodes.contains(where: { $0.path.count > RetainedSceneGeometryLimits.maxDepth }) {
            issues.append("node-depth-limit")
        }
        if Set(nodes.map(\.path)).count != nodes.count {
            issues.append("duplicate-node-path")
        }

        var captureObject: Any = NSNull()
        if let diagnostic {
            if diagnostic.status != .captured { issues.append("runtime-capture-unavailable") }
            if diagnostic.phase != "paintedSceneBeforeEndRenderPass" {
                issues.append("capture-phase-unavailable")
            }
            if nodes.count == reportedNodes.count {
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.sortedKeys]
                    let captureData = try encoder.encode(diagnostic)
                    if captureData.count <= RetainedSceneGeometryLimits.maxSidecarBytes {
                        captureObject = try JSONSerialization.jsonObject(with: captureData)
                    } else {
                        issues.append("capture-byte-limit")
                    }
                } catch {
                    issues.append("capture-encoding-unavailable")
                }
            }
        } else {
            issues.append("runtime-capture-missing")
        }

        let roleTexts = expectedTexts(for: fixtureID)
        let textRoleMatches = roleTexts.map { text in nodes.filter { $0.text == text }.map(\.path) }
        let textRoles = roleTexts.enumerated().map { index, text -> [String: Any] in
            let matches = textRoleMatches[index]
            if matches.count != 1 { issues.append("text-role-match-\(index)") }
            return [
                "role": "text-\(index)",
                "text": text,
                "matchingTreePaths": matches,
                "status": matches.count == 1 ? "unique" : "unavailable",
            ]
        }
        let allCanvasPaths = nodes.filter(\.hasCanvas).map(\.path)
        let canvasMatches =
            fixtureID == "canvas-donut"
            ? donutCanvasCandidates(allCanvasPaths: allCanvasPaths, textRoleMatches: textRoleMatches)
            : allCanvasPaths
        let expectedCanvasCount = fixtureID == "canvas-donut" ? 1 : 0
        if canvasMatches.count != expectedCanvasCount { issues.append("canvas-role-match") }
        let selectedCanvasPath: Any
        if canvasMatches.count == 1 {
            selectedCanvasPath = canvasMatches[0]
        } else {
            selectedCanvasPath = NSNull()
        }

        let inventory = SnapshotSceneGeometryDiagnostics.pathInventory(scene: scene)
        issues.append(contentsOf: inventory.issues)
        let overrideValue: Any
        if overrideState == "1" {
            overrideValue = "1"
        } else {
            overrideValue = NSNull()
        }
        var object: [String: Any] = [
            "schemaVersion": 1,
            "kind": "retained-gallery-geometry-diagnostic",
            "status": issues.isEmpty ? "captured" : "unavailable",
            "issues": issues,
            "qualification": "unqualified",
            "invocationID": invocationID,
            "fixtureID": fixtureID,
            "pngFileName": pngFileName,
            "size": [Int(size.width), Int(size.height)],
            "displayScale": displayScale,
            "appearance": appearance,
            "timestamp": 0,
            "clearColor": "gallery-black",
            "selectedScene": "initial-snapshot-scene",
            "sourceExecutableBinding": "external-receipt-required",
            "pngBinding": "same-invocation-output-external-hash-required",
            "uiFontOverride": [
                "name": "SWIFT_WINDOWSUI_CLASSIC_UI_FONT",
                "state": overrideState,
                "value": overrideValue,
            ],
            "capture": captureObject,
            "reportedNodeCount": reportedNodes.count,
            "textRoles": textRoles,
            "allCanvasNodeCount": allCanvasPaths.count,
            "canvasSelector": fixtureID == "canvas-donut"
                ? "common-ancestor-with-84%-and-capacity-excluding-all-three-legend-texts"
                : "no-canvas-node-expected",
            "canvasMatchingTreePaths": canvasMatches,
            "selectedCanvasTreePath": selectedCanvasPath,
            "expectedCanvasCount": expectedCanvasCount,
            "pathInventory": inventory.object,
            "limits": [
                "maxNodes": RetainedSceneGeometryLimits.maxNodes,
                "maxDepth": RetainedSceneGeometryLimits.maxDepth,
                "maxPaths": RetainedSceneGeometryLimits.maxPaths,
                "maxPathElements": RetainedSceneGeometryLimits.maxPathElements,
                "maxSidecarBytes": RetainedSceneGeometryLimits.maxSidecarBytes,
            ],
            "limitations": [
                "Stored cache sizes are constrained resolved measurements, not raw natural text widths.",
                "Requested text styles do not identify loaded font faces or bytes.",
                "Scene-local primitive references do not establish cross-variant correspondence or Canvas ownership.",
                "Captured describes bounded value coverage, not layout settlement or causal qualification.",
            ],
        ]
        do {
            return GalleryGeometryEncodedSidecar(
                data: try SnapshotSceneGeometryDiagnostics.encodeSidecar(object), isComplete: issues.isEmpty)
        } catch SnapshotSceneGeometryDiagnostics.EncodingError.sidecarTooLarge {
            // A small unavailable receipt is useful, but must never acquire
            // the status of the complete capture that exceeded the byte cap.
            object["status"] = "unavailable"
            object["issues"] = issues + ["sidecar-byte-limit"]
            object["capture"] = NSNull()
            object["textRoles"] = []
            object["canvasMatchingTreePaths"] = []
            object["selectedCanvasTreePath"] = NSNull()
            object["pathInventory"] = [
                "status": "unavailable", "issues": ["sidecar-byte-limit"],
                "scope": "top-level-presented-path-primitives", "canvasOwnership": "unobserved",
            ]
            return GalleryGeometryEncodedSidecar(
                data: try SnapshotSceneGeometryDiagnostics.encodeSidecar(object), isComplete: false)
        }
    }

    package static func expectedTexts(for fixtureID: String) -> [String] {
        switch fixtureID {
        case "typography-scale":
            return [
                "Design system", "A complete type hierarchy", "Headline · Information that matters",
                "Body · Every detail, beautifully clear.", "CAPTION · UPDATED JUST NOW",
            ]
        case "canvas-donut":
            return ["84%", "capacity", "Compute", "Storage", "Network"]
        default:
            return []
        }
    }

    package static func donutCanvasCandidates(
        allCanvasPaths: [[Int]], textRoleMatches: [[[Int]]]
    ) -> [[Int]] {
        guard textRoleMatches.count == 5, textRoleMatches.allSatisfy({ $0.count == 1 }) else { return [] }
        let centerPaths = textRoleMatches.prefix(2).map { $0[0] }
        let legendPaths = textRoleMatches.suffix(3).map { $0[0] }
        // The fixture puts Canvas and both center texts in one ZStack, with
        // the three legend Labels in its sibling VStack. Icon fallbacks may
        // also have canvasDraw; size alone does not identify the authored Canvas.
        return allCanvasPaths.filter { candidate in
            var ancestor = candidate
            for centerPath in centerPaths {
                while !centerPath.starts(with: ancestor) { ancestor.removeLast() }
            }
            return legendPaths.allSatisfy { !$0.starts(with: ancestor) }
        }
    }
}

// MARK: - Gallery Specs

private struct GallerySpec {
    let id: String
    let title: String
    let view: AnyView
    let size: IntSize
    /// The window appearance the entry renders in. Seeds the root environment
    /// exactly as `NSWindow.effectiveAppearance` does, so the entry resolves
    /// the same `ControlPalette` a real window of that appearance resolves.
    let colorScheme: ColorScheme
    /// Non-nil for the interaction-state tier: the runtime input to deliver
    /// before the scene is captured. `nil` renders the view as built.
    let interaction: GalleryInteraction?
    /// Selected asynchronous fixtures settle their production model before the
    /// ordinary retained snapshot. Existing synchronous entries leave this nil.
    let prepare: (@MainActor () async throws -> Void)?

    init(
        id: String,
        title: String,
        view: AnyView,
        size: IntSize = IntSize(width: 200, height: 200),
        colorScheme: ColorScheme = .dark,
        interaction: GalleryInteraction? = nil,
        prepare: (@MainActor () async throws -> Void)? = nil
    ) {
        self.id = id
        self.title = title
        self.view = view
        self.size = size
        self.colorScheme = colorScheme
        self.interaction = interaction
        self.prepare = prepare
    }
}

// MARK: - File browser sample previews

@MainActor
private func fileBrowserGallerySpecs(entryFilter: Set<String>?) -> (
    specs: [GallerySpec], models: [DemoFileBrowserModel]
) {
    let fixtures: [(id: String, title: String, sampleID: String)] = [
        ("file-browser-loaded", "File Browser · Loaded Sample", "sample:welcome"),
        ("file-browser-empty", "File Browser · Empty Sample", "sample:empty"),
        ("file-browser-invalid-utf8", "File Browser · Invalid UTF-8 Sample", "sample:invalid"),
    ]
    var specs: [GallerySpec] = []
    var models: [DemoFileBrowserModel] = []
    for fixture in fixtures {
        if let entryFilter, !entryFilter.contains(fixture.id) { continue }
        // The fixture reader cannot open a file, even if a future fixture
        // accidentally supplies one. The production service still enforces
        // cancellation, the byte limit, and exact UTF-8 decoding.
        let model = DemoFileBrowserModel(
            service: DemoFilePreviewService { source in
                guard case .sample(let bytes) = source else {
                    throw DemoFilePreviewServiceError.invalidFileURL
                }
                return bytes
            })
        models.append(model)
        specs.append(
            GallerySpec(
                id: fixture.id, title: fixture.title,
                view: AnyView(DemoFileBrowserTemplate(model: model).frame(width: 800, height: 480)),
                size: IntSize(width: 800, height: 480),
                prepare: {
                    _ = model.select(id: fixture.sampleID)
                    model.resume()
                    await model.awaitCurrentPreviewRead()
                    guard model.selectedID == fixture.sampleID, model.isActive, !model.isReading,
                        !model.isImporterPresented, model.records == DemoFileBrowserRecord.samples,
                        case .sample(let bytes) = model.selectedRecord?.source
                    else { throw GalleryError.fileBrowserPreparationFailed(id: fixture.id) }
                    if fixture.sampleID == "sample:invalid" {
                        guard model.preview == .failed(DemoFilePreviewServiceError.invalidUTF8.localizedDescription)
                        else { throw GalleryError.fileBrowserPreparationFailed(id: fixture.id) }
                    } else {
                        guard case .ready(let preview) = model.preview,
                            preview.byteCount == bytes.count, preview.text.utf8.elementsEqual(bytes)
                        else { throw GalleryError.fileBrowserPreparationFailed(id: fixture.id) }
                    }
                }))
    }
    return (specs, models)
}

// MARK: - Light appearance tier

/// The gallery's backdrop for an appearance.
///
/// Dark stays pure black — the historical value every dark baseline was taken
/// against. Light uses the appearance's own `windowBackground` rather than
/// white, because most light-mode control surfaces *are* white: on a white
/// page a text field's bezel, a grouped Form's raised surface and a list's
/// body would all be invisible, and the tier would certify nothing.
private func galleryClearColor(for colorScheme: ColorScheme) -> Color {
    switch colorScheme {
    case .dark: return .black
    case .light: return ControlPalette.resolve(colorScheme: .light).windowBackground
    }
}

/// Gallery entries that get a light-appearance twin, by dark-tier id.
///
/// The whole light appearance — `ControlPalette.lightStandard`, the derived
/// `controlTrack`/`segmentedTrackFill` grooves, and every container surface —
/// was pinned only by unit tests reading colour fields. Nothing rendered it,
/// which is how a light-mode Form came to draw a charcoal groove across a
/// white settings pane and survive to final verification: the gate rendered
/// dark only.
///
/// The roster is deliberately a subset. Each id below covers a light-mode
/// role no other entry covers — the recessed grooves (toggle-off, slider,
/// progress), the container surfaces (form-settings, list-data), the control
/// bezels on white (button, text-field, stepper, picker), the hairlines
/// (divider), and the hover/pressed/focus ramps whose light values are
/// otherwise unrendered.
private let lightTierEntryIDs: [String] = [
    "button",
    "button-styles",
    "text-field",
    "toggle",
    "toggle-off",
    "slider",
    "picker",
    "stepper",
    "progress-view",
    "progress-labeled",
    "list-data",
    "form-settings",
    "divider",
    "typography-scale",
    "semantic-labels",
    "group-box",
    "disclosure-expanded",
    "labeled-content",
    "content-unavailable",
    "dashboard-metrics",
    "canvas-sparkline",
    "state-button-hover",
    "state-button-pressed",
    "state-button-focused",
    "state-toggle-pressed",
    "state-field-focused",
    "state-picker-hover",
]

/// Derives the light tier from the dark specs rather than re-declaring the
/// views. A light entry is then *the same view in the other appearance* by
/// construction — it cannot drift into testing a different control, which a
/// hand-maintained parallel list eventually would.
private func lightAppearanceSpecs(from specs: [GallerySpec]) throws -> [GallerySpec] {
    var byID: [String: GallerySpec] = [:]
    for spec in specs {
        byID[spec.id] = spec
    }
    return try lightTierEntryIDs.map { id in
        guard let source = byID[id] else {
            throw GalleryError.unknownLightTierSource(id: id)
        }
        return GallerySpec(
            id: "light-\(id)",
            title: "\(source.title) · light",
            view: source.view,
            size: source.size,
            colorScheme: .light,
            interaction: source.interaction,
            prepare: source.prepare
        )
    }
}

// MARK: - Interaction state tier

/// A control state reached the way a user reaches it — through the runtime's
/// own input entry points — rather than by reaching into the node tree.
///
/// The hover/pressed/focus ramps in `ControlPalette` and `SurfaceChrome` were
/// pinned only by unit tests reading colour fields; nothing rendered them, so
/// a ramp could go visually wrong (a pressed fill lighter than its idle, a
/// focus ring drawn under the control instead of around it) with every
/// assertion still green. These entries put the ramps behind the pixel gate.
private enum GalleryInteraction {
    /// Pointer resting on the control at `point` (client points).
    case hover(Point)
    /// Pointer down and held at `point`.
    case pressed(Point)
    /// Keyboard focus, moved with Tab exactly as the host moves it.
    /// `tabCount` presses land on the nth focusable control.
    case focused(tabCount: Int)

    var describedState: String {
        switch self {
        case .hover: return "hover"
        case .pressed: return "pressed"
        case .focused: return "focused"
        }
    }
}

/// Far enough past any control tween's start that every one of them has
/// completed. `ViewColorAnimation.elapsedFraction` and `tickPropertyAnimations`
/// both clamp to 1, so the settled value is the ramp's END colour —
/// deterministic regardless of the clock the tween was started against.
///
/// This tier deliberately pins *end states*: a baseline of a fraction of a
/// tween is a baseline of the machine's scheduling, not of the design. It is no
/// longer a workaround, though. `RetainedViewRuntime.clock` makes a tween's own
/// timeline addressable, so a mid-tween value is now assertable — in a test
/// rather than in an image gate, which is where a curve belongs:
/// `InteractionTimelineFidelityTests` samples exactly those frames.
private let gallerySettledTimestamp: Double = 1e12

@MainActor
private func applyInteraction(
    _ interaction: GalleryInteraction,
    to runtime: RetainedViewRuntime
) {
    switch interaction {
    case .hover(let point):
        runtime.pointerMoved(to: point)
    case .pressed(let point):
        runtime.pointerMoved(to: point)
        runtime.pointerDown(at: point)
    case .focused(let tabCount):
        for _ in 0..<max(1, tabCount) {
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))
        }
    }
    // Settle every tween the input started, then render at the same instant so
    // the scene and the animation clock agree.
    runtime.tickAnimations(at: gallerySettledTimestamp)
}

/// The interaction-state tier: four control families × their state ramps.
///
/// Each control is pinned to a known frame at the canvas origin so the driving
/// point is derivable by hand and stays true if the surrounding list is
/// reordered.
@MainActor
private func interactionStateSpecs() -> [GallerySpec] {
    // Button: 120x36 at the origin.
    let buttonFrame = (width: 120.0, height: 36.0)
    let buttonCentre = Point(x: buttonFrame.width / 2, y: buttonFrame.height / 2)
    func button(_ title: String) -> AnyView {
        AnyView(
            Button(title) {}
                .frame(width: buttonFrame.width, height: buttonFrame.height)
        )
    }

    // Toggle: the switch alone. A labelled `Toggle` lays its row out at
    // content width and leading-aligned, so the switch's position depends on
    // the label's measured text — `labelsHidden()` makes the hit target the
    // frame itself, and the centre derivable rather than measured off a PNG.
    let toggleFrame = (width: 60.0, height: 36.0)
    let togglePoint = Point(x: toggleFrame.width / 2, y: toggleFrame.height / 2)
    func toggle() -> AnyView {
        AnyView(
            Toggle("Sync", isOn: .constant(true))
                .labelsHidden()
                .frame(width: toggleFrame.width, height: toggleFrame.height)
        )
    }

    // Text field: 160x32 at the origin. No pointer point is derived for it —
    // the field ramp below is focus-driven only (see the note on the specs).
    let fieldFrame = (width: 160.0, height: 32.0)
    func field() -> AnyView {
        AnyView(
            TextField("Name", text: .constant("Ada"))
                .frame(width: fieldFrame.width, height: fieldFrame.height)
        )
    }

    // Segmented picker, label hidden so the band fills the frame instead of
    // sharing it with a caption (which squashes a 30pt control to ~10pt). The
    // point lands in the LAST segment — the unselected one, since a hover ramp
    // under the selected segment's fill is indistinguishable from selection.
    //
    // 240pt, matching the base `picker` entry. `state-picker-pressed` used to
    // certify "Thr…" as the correct rendering of a segment title; widening the
    // entry is *not* what fixed that (the cause was a title cell sized to its
    // own string, and it is fixed in `Picker` — see
    // `ControlChromePolishTests.testSegmentTitleCellSpansTheSegment…`). The
    // width is here so the ramp certifies chrome and only chrome: at 180 each
    // segment held "Three" with about a point to spare, which is close enough
    // that a font-metric change would put the ramp back in the business of
    // testing line breaking. A deliberately narrow frame belongs in
    // `ControlChromePolishTests`, where it is the subject.
    let pickerFrame = (width: 240.0, height: 30.0)
    /// Canvas for the picker ramp: the 240pt track plus the room its focus ring
    /// needs, since the ring is drawn outside the control's bounds.
    let pickerCanvas = IntSize(width: 280, height: 200)
    let pickerTrailingSegment = Point(x: pickerFrame.width - 30, y: pickerFrame.height / 2)
    func picker() -> AnyView {
        AnyView(
            Picker("Mode", selection: .constant(0)) {
                Text("One").tag(0)
                Text("Two").tag(1)
                Text("Three").tag(2)
            }
            .pickerStyle(SegmentedPickerStyle())
            .labelsHidden()
            .frame(width: pickerFrame.width, height: pickerFrame.height)
        )
    }

    return [
        // Button ramp
        GallerySpec(id: "state-button-idle", title: "Button · idle", view: button("Action")),
        GallerySpec(
            id: "state-button-hover", title: "Button · hover", view: button("Action"),
            interaction: .hover(buttonCentre)),
        GallerySpec(
            id: "state-button-pressed", title: "Button · pressed", view: button("Action"),
            interaction: .pressed(buttonCentre)),
        GallerySpec(
            id: "state-button-focused", title: "Button · focused", view: button("Action"),
            interaction: .focused(tabCount: 1)),
        GallerySpec(
            id: "state-button-disabled", title: "Button · disabled",
            view: AnyView(
                Button("Action") {}
                    .disabled(true)
                    .frame(width: buttonFrame.width, height: buttonFrame.height)
            )),

        // Toggle ramp
        GallerySpec(id: "state-toggle-idle", title: "Toggle · idle", view: toggle()),
        GallerySpec(
            id: "state-toggle-hover", title: "Toggle · hover", view: toggle(),
            interaction: .hover(togglePoint)),
        GallerySpec(
            id: "state-toggle-pressed", title: "Toggle · pressed", view: toggle(),
            interaction: .pressed(togglePoint)),
        GallerySpec(
            id: "state-toggle-disabled", title: "Toggle · disabled",
            view: AnyView(
                Toggle("Sync", isOn: .constant(true))
                    .labelsHidden()
                    .disabled(true)
                    .frame(width: toggleFrame.width, height: toggleFrame.height)
            )),

        // Text field ramp. No hover entry: a text field's bezel does not
        // respond to the pointer on macOS, and this stack matches it — only
        // `Controls.button` installs a hover ramp, so a `field-hover` entry
        // would sit in the gate re-certifying the idle render forever. Focus
        // is the state a field actually has, and it is pinned below.
        GallerySpec(id: "state-field-idle", title: "TextField · idle", view: field()),
        GallerySpec(
            id: "state-field-focused", title: "TextField · focused", view: field(),
            interaction: .focused(tabCount: 1)),
        GallerySpec(
            id: "state-field-disabled", title: "TextField · disabled",
            view: AnyView(
                TextField("Name", text: .constant("Ada"))
                    .disabled(true)
                    .frame(width: fieldFrame.width, height: fieldFrame.height)
            )),

        // Segmented picker ramp
        GallerySpec(
            id: "state-picker-idle", title: "Picker · idle", view: picker(), size: pickerCanvas),
        GallerySpec(
            id: "state-picker-hover", title: "Picker · hover", view: picker(), size: pickerCanvas,
            interaction: .hover(pickerTrailingSegment)),
        GallerySpec(
            id: "state-picker-pressed", title: "Picker · pressed", view: picker(), size: pickerCanvas,
            interaction: .pressed(pickerTrailingSegment)),
        GallerySpec(
            id: "state-picker-focused", title: "Picker · focused", view: picker(), size: pickerCanvas,
            interaction: .focused(tabCount: 1)),
    ]
}

private struct GalleryBitmapFontAttributionEnvelope: Encodable {
    struct Runtime: Encodable {
        let os: String
        let architecture: String

        static var current: Self {
            let version = ProcessInfo.processInfo.operatingSystemVersion
            #if arch(x86_64)
                let architecture = "x86_64"
            #elseif arch(arm64)
                let architecture = "arm64"
            #else
                let architecture = "unknown"
            #endif
            return Self(
                os: "Windows \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
                architecture: architecture
            )
        }
    }

    let schemaVersion = 1
    let invocationID: String
    let fixtureID: String
    let pngFileName: String
    let status: String
    let runtime: Runtime
    let report: NativeBitmapFontAttributionReport
}

/// This envelope is selected only by an explicit V2 request. V1's DTO and
/// encoding are deliberately unchanged; consumers must select their parser.
private struct GalleryBitmapFontAttributionEnvelopeV2: Encodable {
    let schemaVersion = 2
    let invocationID: String
    let fixtureID: String
    let pngFileName: String
    let status: String
    let runtime: GalleryBitmapFontAttributionEnvelope.Runtime
    let report: NativeBitmapFontAttributionReportV2
}

private enum GalleryError: Error, CustomStringConvertible {
    case interactionHadNoEffect(id: String, state: String)
    case unknownLightTierSource(id: String)
    case fileBrowserPreparationFailed(id: String)
    case invalidBitmapFontAttribution
    case bitmapFontAttributionOutputUnavailable
    case invalidGeometryDiagnostics
    case geometryDiagnosticsOutputUnavailable
    case geometryDiagnosticsIncomplete

    var description: String {
        switch self {
        case .invalidBitmapFontAttribution:
            return "Bitmap font attribution requires paired output/invocation flags and only symbol-palette or stepper."
        case .bitmapFontAttributionOutputUnavailable:
            return "Bitmap font attribution requires fresh owned output and a bounded writable sidecar."
        case .invalidGeometryDiagnostics:
            return
                "Geometry diagnostics require paired flags, exact typography-scale/canvas-donut selection, known arguments, no bitmap attribution, default-or-1 UI-font mode, and fixed noninteractive fixtures."
        case .geometryDiagnosticsOutputUnavailable:
            return "Geometry diagnostics require fresh PNG/index outputs and a new separate sidecar directory."
        case .geometryDiagnosticsIncomplete:
            return "Geometry diagnostic evidence is unavailable or incomplete; PNG and index outputs were retained."
        case .fileBrowserPreparationFailed(let id):
            return
                "File browser fixture '\(id)' did not finish its expected built-in sample preview; no PNG was written."
        case .interactionHadNoEffect(let id, let state):
            return """
                Gallery entry '\(id)' declares the '\(state)' state but renders \
                pixel-identical to its own idle render. The interaction did not \
                reach the control — check the point against the control's frame, \
                or the tab count against the focusable order.
                """
        case .unknownLightTierSource(let id):
            return """
                The light tier names '\(id)', which is not a gallery entry. A \
                light entry is derived from its dark twin, so a typo here would \
                silently drop an appearance from the gate rather than render it.
                """
        }
    }
}

// MARK: - Gallery Entry

private struct GalleryEntry {
    let id: String
    let title: String
    let filename: String
    let size: IntSize
    let colorScheme: ColorScheme
    let primitiveCount: Int
    let layerCount: Int
}

// MARK: - HTML Report

private enum GalleryCategory: String, CaseIterable {
    case components
    case compositions
    case typography
    case layouts
    case graphics
    case interactions

    var title: String {
        switch self {
        case .components: return "Components"
        case .compositions: return "Compositions"
        case .typography: return "Typography"
        case .layouts: return "Layouts"
        case .graphics: return "Graphics"
        case .interactions: return "Interaction states"
        }
    }
}

private func galleryCategory(for entry: GalleryEntry) -> GalleryCategory {
    let identifier =
        entry.id.hasPrefix("light-")
        ? String(entry.id.dropFirst("light-".count))
        : entry.id

    if identifier.hasPrefix("state-") {
        return .interactions
    }

    let compositionIdentifiers: Set<String> = [
        "controls-panel", "dashboard-metrics", "form-settings", "status-badges", "tinted-controls",
        "file-browser-loaded", "file-browser-empty", "file-browser-invalid-utf8",
    ]
    if compositionIdentifiers.contains(identifier) {
        return .compositions
    }

    let typographyIdentifiers: Set<String> = [
        "semantic-labels", "symbol-palette", "text", "typography-scale",
    ]
    if typographyIdentifiers.contains(identifier) {
        return .typography
    }

    let componentPrefixes = [
        "button", "content-unavailable", "disclosure", "divider", "focus", "gauge", "group-box",
        "labeled-content", "link", "menu", "picker", "progress", "secure-field", "slider", "stepper",
        "text-field", "text-input", "toggle",
    ]
    if componentPrefixes.contains(where: { identifier.hasPrefix($0) }) {
        return .components
    }

    let layoutPrefixes = [
        "for-each", "form", "geometry", "grid", "group", "hstack", "if-else", "list", "navigation",
        "scroll", "spacer", "tab", "vstack", "zstack",
    ]
    if layoutPrefixes.contains(where: { identifier.hasPrefix($0) }) {
        return .layouts
    }

    return .graphics
}

/// Escapes every interpolated string before it reaches text or attribute HTML.
/// The report is generated locally, but fixture titles still must not become
/// executable markup if a future entry includes punctuation or user text.
private func galleryEscapedHTML(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}

private func writeGalleryHTML(entries: [GalleryEntry], to url: URL) throws {
    let lightCount = entries.filter { $0.colorScheme == .light }.count
    let stateCount = entries.filter { galleryCategory(for: $0) == .interactions }.count
    let primitiveCount = entries.reduce(0) { $0 + $1.primitiveCount }

    let categoryButtons = GalleryCategory.allCases.compactMap { category -> String? in
        let count = entries.filter { galleryCategory(for: $0) == category }.count
        guard count > 0 else { return nil }
        return """
            <button class="filter-chip" type="button" data-filter-kind="category" \
            data-filter-value="\(category.rawValue)" aria-pressed="false">\
            \(galleryEscapedHTML(category.title)) <span class="chip-count">\(count)</span></button>
            """
    }.joined(separator: "\n")

    let cards = entries.map { entry in
        // The wrapper carries the entry's own appearance: a light-tier PNG
        // reviewed inside a black tile reads as a rendering bug that is not
        // there, and hides the one that is.
        let wrapperClass = entry.colorScheme == .light ? "image-wrapper light" : "image-wrapper"
        let appearance = entry.colorScheme == .light ? "light" : "dark"
        let category = galleryCategory(for: entry)
        let state = category == .interactions ? "interaction" : "reference"
        let identifier = galleryEscapedHTML(entry.id)
        let title = galleryEscapedHTML(entry.title)
        let filename = galleryEscapedHTML(entry.filename)
        let searchText = galleryEscapedHTML(
            "\(entry.id) \(entry.title) \(category.title) \(appearance)".lowercased()
        )
        return """
            <article class="card" data-id="\(identifier)" data-category="\(category.rawValue)" \
            data-appearance="\(appearance)" data-state="\(state)" \
            data-primitives="\(entry.primitiveCount)" data-search="\(searchText)">
                <a class="\(wrapperClass)" href="\(filename)" target="_blank" rel="noopener" \
                aria-label="Open full-size snapshot for \(title)">
                    <img src="\(filename)" alt="\(title)" width="\(entry.size.width)" \
                    height="\(entry.size.height)" loading="lazy">
                </a>
                <div class="info">
                    <div class="card-heading">
                        <div>
                            <div class="eyebrow">\(galleryEscapedHTML(category.title))</div>
                            <div class="title">\(title)</div>
                        </div>
                        <span class="appearance-badge \(appearance)">\(appearance)</span>
                    </div>
                    <div class="fixture-row">
                        <code class="fixture-id">\(identifier)</code>
                        <button class="copy-button" type="button" data-copy="\(identifier)" \
                        aria-label="Copy fixture identifier \(identifier)">Copy</button>
                    </div>
                    <div class="meta">\(entry.size.width) × \(entry.size.height) px \
                    · \(entry.primitiveCount) primitives · \(entry.layerCount) layers</div>
                </div>
            </article>
            """
    }.joined(separator: "\n")

    let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta name="color-scheme" content="dark">
            <title>SwiftWindowsUI Gallery</title>
            <style>
                :root {
                    color-scheme: dark;
                    --surface: #111820;
                    --surface-raised: #17212c;
                    --surface-muted: #0d141c;
                    --border: rgba(171, 188, 208, 0.14);
                    --text: #ecf2f8;
                    --muted: #91a1b4;
                    --accent: #7fd2c9;
                }
                * { box-sizing: border-box; }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                    margin: 0;
                    background:
                        radial-gradient(ellipse at 8% 0%, rgba(74, 155, 145, 0.12), transparent 32%),
                        radial-gradient(ellipse at 95% 12%, rgba(90, 114, 174, 0.1), transparent 28%),
                        #0a1017;
                    color: var(--text);
                    min-height: 100vh;
                }
                button, input { font: inherit; }
                button:focus-visible, input:focus-visible, a:focus-visible {
                    outline: 2px solid var(--accent);
                    outline-offset: 3px;
                }
                .shell { width: min(1600px, calc(100% - 56px)); margin: 0 auto; }
                .hero { padding: 64px 0 34px; }
                .kicker, .eyebrow {
                    color: var(--accent);
                    font-size: 11px;
                    font-weight: 650;
                    letter-spacing: 0.09em;
                    text-transform: uppercase;
                }
                h1 {
                    font-size: clamp(34px, 5vw, 54px);
                    letter-spacing: -0.055em;
                    line-height: 1.03;
                    margin: 13px 0 12px;
                }
                .subtitle {
                    color: var(--muted);
                    font-size: 15px;
                    line-height: 1.65;
                    margin: 0;
                    max-width: 670px;
                }
                .statistics {
                    display: grid;
                    gap: 12px;
                    grid-template-columns: repeat(4, minmax(0, 1fr));
                    margin-top: 29px;
                    max-width: 800px;
                }
                .stat {
                    background: rgba(17, 24, 32, 0.82);
                    border: 1px solid var(--border);
                    border-radius: 13px;
                    padding: 14px 15px;
                }
                .stat-value { font-size: 22px; font-weight: 650; letter-spacing: -0.035em; }
                .stat-label { color: var(--muted); font-size: 11px; margin-top: 4px; }
                .toolbar {
                    background: rgba(10, 16, 23, 0.91);
                    border-bottom: 1px solid var(--border);
                    margin-bottom: 24px;
                    padding: 16px 0 18px;
                    position: sticky;
                    top: 0;
                    z-index: 2;
                }
                @supports (backdrop-filter: blur(16px)) {
                    .toolbar { backdrop-filter: blur(16px); }
                }
                .toolbar-top, .filter-row, .filter-group {
                    align-items: center;
                    display: flex;
                    flex-wrap: wrap;
                    gap: 10px;
                }
                .toolbar-top { justify-content: space-between; }
                .search-wrap { flex: 1 1 280px; max-width: 460px; position: relative; }
                .search {
                    background: var(--surface);
                    border: 1px solid var(--border);
                    border-radius: 10px;
                    color: var(--text);
                    font-size: 13px;
                    height: 42px;
                    padding: 0 45px 0 14px;
                    width: 100%;
                }
                .search::placeholder { color: var(--muted); }
                kbd {
                    background: var(--surface-raised);
                    border: 1px solid var(--border);
                    border-radius: 5px;
                    color: var(--muted);
                    font-size: 11px;
                    padding: 2px 6px;
                    position: absolute;
                    right: 13px;
                    top: 11px;
                }
                .filter-row { gap: 8px; margin-top: 13px; }
                .filter-label {
                    color: var(--muted);
                    font-size: 11px;
                    letter-spacing: 0.04em;
                    margin-right: 2px;
                }
                .filter-chip {
                    background: transparent;
                    border: 1px solid var(--border);
                    border-radius: 999px;
                    color: var(--muted);
                    cursor: pointer;
                    font-size: 12px;
                    padding: 7px 11px;
                }
                .filter-chip:hover { background: var(--surface-raised); color: var(--text); }
                .filter-chip[aria-pressed="true"] {
                    background: rgba(127, 210, 201, 0.12);
                    border-color: rgba(127, 210, 201, 0.32);
                    color: var(--accent);
                }
                .chip-count { color: var(--muted); font-size: 10px; margin-left: 3px; }
                .filter-divider { background: var(--border); height: 20px; margin: 0 3px; width: 1px; }
                .results-summary { color: var(--muted); font-size: 12px; }
                .results-summary strong { color: var(--text); }
                .grid {
                    display: grid;
                    gap: 18px;
                    grid-template-columns: repeat(auto-fill, minmax(min(100%, 315px), 1fr));
                    padding-bottom: 60px;
                }
                .card {
                    background: var(--surface);
                    border: 1px solid var(--border);
                    border-radius: 14px;
                    overflow: hidden;
                    transition: border-color 160ms ease, transform 160ms ease;
                }
                .card:hover { border-color: rgba(127, 210, 201, 0.38); transform: translateY(-2px); }
                .card[hidden] { display: none; }
                .image-wrapper {
                    background: #000;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    min-height: 230px;
                    padding: 15px;
                    text-decoration: none;
                }
                .image-wrapper.light { background: #ececec; }
                .image-wrapper.light img { border-color: #c8c8c8; }
                img {
                    border: 1px solid rgba(171, 188, 208, 0.18);
                    border-radius: 5px;
                    display: block;
                    height: auto;
                    max-height: 280px;
                    max-width: 100%;
                    object-fit: contain;
                }
                .info {
                    border-top: 1px solid var(--border);
                    padding: 15px 15px 13px;
                }
                .card-heading { align-items: flex-start; display: flex; justify-content: space-between; }
                .eyebrow { font-size: 9px; margin-bottom: 6px; }
                .title {
                    font-size: 14px;
                    font-weight: 600;
                    line-height: 1.35;
                }
                .appearance-badge {
                    border: 1px solid var(--border);
                    border-radius: 999px;
                    color: var(--muted);
                    font-size: 10px;
                    padding: 4px 8px;
                    white-space: nowrap;
                }
                .appearance-badge.light { color: #f1c97c; }
                .fixture-row {
                    align-items: center;
                    display: flex;
                    gap: 8px;
                    justify-content: space-between;
                    margin-top: 13px;
                }
                .fixture-id, .meta {
                    font-family: ui-monospace, SFMono-Regular, "Cascadia Code", monospace;
                }
                .fixture-id { color: #b9cad8; font-size: 10px; overflow-wrap: anywhere; }
                .copy-button {
                    background: transparent;
                    border: 1px solid var(--border);
                    border-radius: 6px;
                    color: var(--muted);
                    cursor: pointer;
                    flex-shrink: 0;
                    font-size: 10px;
                    padding: 4px 7px;
                }
                .copy-button:hover { border-color: rgba(127, 210, 201, 0.4); color: var(--accent); }
                .copy-button.copied { color: var(--accent); }
                .meta {
                    color: var(--muted);
                    font-size: 10px;
                    line-height: 1.5;
                    margin-top: 11px;
                }
                .empty-state {
                    border: 1px dashed var(--border);
                    border-radius: 14px;
                    color: var(--muted);
                    padding: 56px 22px;
                    text-align: center;
                }
                .empty-state[hidden] { display: none; }
                @media (max-width: 720px) {
                    .shell { width: calc(100% - 32px); }
                    .hero { padding-top: 42px; }
                    .statistics { grid-template-columns: repeat(2, minmax(0, 1fr)); }
                    .toolbar { position: static; }
                    .toolbar-top { align-items: stretch; }
                    .search-wrap { max-width: none; }
                    .filter-divider { display: none; }
                }
                @media (prefers-reduced-motion: reduce) {
                    *, *::before, *::after { scroll-behavior: auto !important; transition: none !important; }
                }
            </style>
        </head>
        <body>
            <header class="shell hero">
                <div class="kicker">SwiftWindowsUI / Visual laboratory</div>
                <h1>The component gallery.</h1>
                <p class="subtitle">Real retained-runtime snapshots across controls, layouts, graphics, \
                interaction states, and complete compositions. Every image is captured directly from the \
                renderer-neutral scene.</p>
                <div class="statistics" aria-label="Gallery statistics">
                    <div class="stat"><div class="stat-value">\(entries.count)</div>\
                    <div class="stat-label">Visual fixtures</div></div>
                    <div class="stat"><div class="stat-value">\(lightCount)</div>\
                    <div class="stat-label">Light appearances</div></div>
                    <div class="stat"><div class="stat-value">\(stateCount)</div>\
                    <div class="stat-label">Interaction states</div></div>
                    <div class="stat"><div class="stat-value">\(primitiveCount)</div>\
                    <div class="stat-label">Scene primitives</div></div>
                </div>
            </header>
            <section class="toolbar" aria-label="Gallery filters">
                <div class="shell">
                    <div class="toolbar-top">
                        <label class="search-wrap">
                            <input class="search" id="gallery-search" type="search" \
                            placeholder="Search components, identifiers, or categories" \
                            aria-label="Search visual fixtures" autocomplete="off">
                            <kbd aria-hidden="true">/</kbd>
                        </label>
                        <div class="results-summary" id="results-summary" aria-live="polite">\
                        <strong>\(entries.count)</strong> fixtures visible</div>
                    </div>
                    <div class="filter-row" aria-label="Appearance and state filters">
                        <span class="filter-label">Appearance</span>
                        <button class="filter-chip" type="button" data-filter-kind="appearance" \
                        data-filter-value="all" aria-pressed="true">All</button>
                        <button class="filter-chip" type="button" data-filter-kind="appearance" \
                        data-filter-value="dark" aria-pressed="false">Dark</button>
                        <button class="filter-chip" type="button" data-filter-kind="appearance" \
                        data-filter-value="light" aria-pressed="false">Light</button>
                        <span class="filter-divider" aria-hidden="true"></span>
                        <span class="filter-label">Capture</span>
                        <button class="filter-chip" type="button" data-filter-kind="state" \
                        data-filter-value="all" aria-pressed="true">All</button>
                        <button class="filter-chip" type="button" data-filter-kind="state" \
                        data-filter-value="reference" aria-pressed="false">Reference</button>
                        <button class="filter-chip" type="button" data-filter-kind="state" \
                        data-filter-value="interaction" aria-pressed="false">Interactive</button>
                    </div>
                    <div class="filter-row" aria-label="Component category filters">
                        <span class="filter-label">Category</span>
                        <button class="filter-chip" type="button" data-filter-kind="category" \
                        data-filter-value="all" aria-pressed="true">Everything</button>
                        \(categoryButtons)
                    </div>
                </div>
            </section>
            <main class="shell">
                <div class="grid" id="gallery-grid">
                    \(cards)
                </div>
                <div class="empty-state" id="empty-state" hidden>No fixtures match these filters. \
                Clear the search or choose another appearance.</div>
            </main>
            <script>
                (() => {
                    "use strict";
                    const search = document.getElementById("gallery-search");
                    const summary = document.getElementById("results-summary");
                    const empty = document.getElementById("empty-state");
                    const cards = Array.from(document.querySelectorAll(".card"));
                    const filters = { appearance: "all", category: "all", state: "all" };

                    function updateResults() {
                        const query = search.value.trim().toLowerCase();
                        let visible = 0;
                        let primitives = 0;
                        for (const card of cards) {
                            const matches =
                                (!query || card.dataset.search.includes(query)) &&
                                (filters.appearance === "all" || card.dataset.appearance === filters.appearance) &&
                                (filters.category === "all" || card.dataset.category === filters.category) &&
                                (filters.state === "all" || card.dataset.state === filters.state);
                            card.hidden = !matches;
                            if (matches) {
                                visible += 1;
                                primitives += Number(card.dataset.primitives || 0);
                            }
                        }
                        summary.replaceChildren();
                        const count = document.createElement("strong");
                        count.textContent = String(visible);
                        summary.append(count, ` fixtures visible · ${primitives} primitives`);
                        empty.hidden = visible !== 0;
                    }

                    document.addEventListener("click", async (event) => {
                        const filter = event.target.closest("[data-filter-kind]");
                        if (filter) {
                            const kind = filter.dataset.filterKind;
                            filters[kind] = filter.dataset.filterValue;
                            for (const candidate of document.querySelectorAll("[data-filter-kind]")) {
                                if (candidate.dataset.filterKind === kind) {
                                    candidate.setAttribute("aria-pressed", String(candidate === filter));
                                }
                            }
                            updateResults();
                            return;
                        }

                        const copy = event.target.closest("[data-copy]");
                        if (!copy) return;
                        try {
                            if (navigator.clipboard && window.isSecureContext) {
                                await navigator.clipboard.writeText(copy.dataset.copy);
                            } else {
                                const selection = document.createElement("textarea");
                                selection.value = copy.dataset.copy;
                                selection.style.position = "fixed";
                                selection.style.opacity = "0";
                                document.body.append(selection);
                                selection.select();
                                const copied = document.execCommand("copy");
                                selection.remove();
                                if (!copied) throw new Error("Clipboard unavailable");
                            }
                            copy.textContent = "Copied";
                            copy.classList.add("copied");
                            window.setTimeout(() => {
                                copy.textContent = "Copy";
                                copy.classList.remove("copied");
                            }, 1200);
                        } catch {
                            copy.textContent = "Unavailable";
                        }
                    });

                    search.addEventListener("input", updateResults);
                    document.addEventListener("keydown", (event) => {
                        const editing = /^(INPUT|TEXTAREA|SELECT)$/.test(event.target.tagName);
                        if (event.key === "/" && !editing) {
                            event.preventDefault();
                            search.focus();
                        } else if (event.key === "Escape" && document.activeElement === search) {
                            search.value = "";
                            updateResults();
                            search.blur();
                        }
                    });
                })();
            </script>
        </body>
        </html>
        """
    try html.write(to: url, atomically: true, encoding: .utf8)
}
