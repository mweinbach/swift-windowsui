import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
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

        let gallerySpecs: [GallerySpec] = [
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
            GallerySpec(
                id: "picker", title: "Picker",
                view: AnyView(
                    Picker("Color", selection: .constant(1)) {
                        Text("Red").tag(0)
                        Text("Green").tag(1)
                        Text("Blue").tag(2)
                    }
                    .frame(width: 160, height: 40)
                )),
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
                    .frame(width: 170, height: 160)
                )),
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
                    .frame(width: 240, height: 220)
                ),
                size: IntSize(width: 260, height: 240)),
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
        ]

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
                clearColor: .black
            )
            let bitmap = GPUIRawSceneRasterizer.rasterize(snapshot.scene, size: snapshot.size)
            let filename = "\(spec.id).png"
            let url = outputDir.appendingPathComponent(filename)
            try bitmap.writePNG(to: url)

            entries.append(
                GalleryEntry(
                    id: spec.id,
                    title: spec.title,
                    filename: filename,
                    size: spec.size,
                    primitiveCount: snapshot.scene.primitiveCount,
                    layerCount: snapshot.scene.layers.count
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

    init(id: String, title: String, view: AnyView, size: IntSize = IntSize(width: 200, height: 200)) {
        self.id = id
        self.title = title
        self.view = view
        self.size = size
    }
}

// MARK: - Gallery Entry

private struct GalleryEntry {
    let id: String
    let title: String
    let filename: String
    let size: IntSize
    let primitiveCount: Int
    let layerCount: Int
}

// MARK: - HTML Report

private func writeGalleryHTML(entries: [GalleryEntry], to url: URL) throws {
    let cards = entries.map { entry in
        """
        <div class="card">
            <div class="image-wrapper">
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
            <div class="subtitle">\(entries.count) snapshots &middot; responsive canvases &middot; raw-scene backend &middot; shapes, effects, and real controls</div>
            <div class="grid">
                \(cards)
            </div>
        </body>
        </html>
        """
    try html.write(to: url, atomically: true, encoding: .utf8)
}
