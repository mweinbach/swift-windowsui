import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsUI
import WinSwiftUI

@main
struct SwiftWindowsUIGalleryTool {
    @MainActor
    static func main() throws {
        // Minimal additive CLI:
        //   --entries <csv>     only render the listed entry ids
        //   --output-dir <path> write PNGs/index somewhere else
        // Defaults keep the historical behavior (all entries, artifacts/gallery).
        var outputDirPath = "artifacts/gallery"
        var entryFilter: Set<String>?
        var argumentIndex = 1
        let arguments = CommandLine.arguments
        while argumentIndex < arguments.count {
            let argument = arguments[argumentIndex]
            if argument == "--output-dir", argumentIndex + 1 < arguments.count {
                outputDirPath = arguments[argumentIndex + 1]
                argumentIndex += 1
            } else if argument == "--entries", argumentIndex + 1 < arguments.count {
                entryFilter = Set(
                    arguments[argumentIndex + 1]
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                )
                argumentIndex += 1
            }
            argumentIndex += 1
        }

        let outputDir = URL(fileURLWithPath: outputDirPath)
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
                        .frame(width: 100, height: 100).contrast(1.0)
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
        let darkSpecs = baseSpecs + interactionStateSpecs()
        let gallerySpecs = try darkSpecs + lightAppearanceSpecs(from: darkSpecs)

        var entries: [GalleryEntry] = []
        let displayScale = 1.0

        for spec in gallerySpecs {
            if let entryFilter, !entryFilter.contains(spec.id) {
                continue
            }
            let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
                of: spec.view,
                size: spec.size,
                displayScale: displayScale,
                colorScheme: spec.colorScheme,
                clearColor: galleryClearColor(for: spec.colorScheme)
            )

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

    init(
        id: String,
        title: String,
        view: AnyView,
        size: IntSize = IntSize(width: 200, height: 200),
        colorScheme: ColorScheme = .dark,
        interaction: GalleryInteraction? = nil
    ) {
        self.id = id
        self.title = title
        self.view = view
        self.size = size
        self.colorScheme = colorScheme
        self.interaction = interaction
    }
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
            interaction: source.interaction
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

private enum GalleryError: Error, CustomStringConvertible {
    case interactionHadNoEffect(id: String, state: String)
    case unknownLightTierSource(id: String)

    var description: String {
        switch self {
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

private func writeGalleryHTML(entries: [GalleryEntry], to url: URL) throws {
    let cards = entries.map { entry in
        // The wrapper carries the entry's own appearance: a light-tier PNG
        // reviewed inside a black tile reads as a rendering bug that is not
        // there, and hides the one that is.
        let wrapperClass = entry.colorScheme == .light ? "image-wrapper light" : "image-wrapper"
        return """
            <div class="card">
                <div class="\(wrapperClass)">
                    <img src="\(entry.filename)" alt="\(entry.title)" width="\(entry.size.width)" height="\(entry.size.height)">
                </div>
                <div class="info">
                    <div class="title">\(entry.title)</div>
                    <div class="meta">\(entry.primitiveCount) primitives · \(entry.layerCount) layers</div>
                </div>
            </div>
            """
    }.joined(separator: "\n")

    let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <title>SwiftWindowsUI Gallery</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                    margin: 24px;
                    background: #0f1419;
                    color: #e6edf3;
                }
                h1 { font-size: 22px; margin-bottom: 6px; }
                .subtitle { color: #8b949e; font-size: 13px; margin-bottom: 24px; }
                .grid {
                    display: grid;
                    grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
                    gap: 16px;
                }
                .card {
                    background: #161b22;
                    border: 1px solid #30363d;
                    border-radius: 8px;
                    overflow: hidden;
                }
                .image-wrapper {
                    background: #000;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    padding: 8px;
                }
                .image-wrapper.light { background: #ececec; }
                .image-wrapper.light img { border-color: #c8c8c8; }
                img {
                    display: block;
                    max-width: 100%;
                    height: auto;
                    border-radius: 4px;
                    border: 1px solid #30363d;
                    image-rendering: pixelated;
                }
                .info {
                    padding: 10px 12px;
                    border-top: 1px solid #30363d;
                }
                .title {
                    font-size: 13px;
                    font-weight: 600;
                    margin-bottom: 4px;
                }
                .meta {
                    font-size: 11px;
                    color: #8b949e;
                    font-family: ui-monospace, SFMono-Regular, monospace;
                }
            </style>
        </head>
        <body>
            <h1>SwiftWindowsUI Gallery</h1>
            <div class="subtitle">\(entries.count) snapshots &middot; dark and light appearances &middot; raw-scene backend &middot; shapes, effects, and real controls</div>
            <div class="grid">
                \(cards)
            </div>
        </body>
        </html>
        """
    try html.write(to: url, atomically: true, encoding: .utf8)
}
