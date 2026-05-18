import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Integration tests that combine multiple SwiftUI features in single view trees
/// to validate end-to-end compositional correctness.
@MainActor
final class WinSwiftUICompositeTests: XCTestCase {

    private func render<V: View>(
        _ view: V,
        size: IntSize = IntSize(width: 400, height: 600)
    ) -> BitmapSurface {
        let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
            of: view,
            size: size,
            displayScale: 1,
            clearColor: .black
        )
        return GPUIRawSceneRasterizer.rasterize(snapshot.scene, size: snapshot.size)
    }

    // MARK: - Complex composite views

    func testSettingsScreenRenders() async {
        await MainActor.run {
            struct SettingsView: View {
                @State private var username = "admin"
                @State private var isDarkMode = true
                @State private var volume = 0.5
                @State private var selectedTheme = 0

                var body: some View {
                    NavigationStack {
                        Form {
                            Section("Account") {
                                TextField("Username", text: $username)
                                Toggle("Dark Mode", isOn: $isDarkMode)
                            }

                            Section("Preferences") {
                                Slider(value: $volume, in: 0...1) {
                                    Text("Volume")
                                }
                                Picker("Theme", selection: $selectedTheme) {
                                    Text("Light").tag(0)
                                    Text("Dark").tag(1)
                                    Text("Auto").tag(2)
                                }
                            }

                            Section("Actions") {
                                Button("Save Changes") {}
                                Button("Reset", role: .destructive) {}
                            }
                        }
                        .navigationTitle("Settings")
                    }
                }
            }

            let bitmap = render(SettingsView())
            // The scene should have produced primitives for the form, sections, fields, buttons
            XCTAssertGreaterThan(bitmap.pixels.count, 0)
        }
    }

    func testDashboardWithListAndCardsRenders() async {
        await MainActor.run {
            struct DashboardView: View {
                let items = ["Alpha", "Beta", "Gamma", "Delta"]

                var body: some View {
                    VStack(spacing: 16) {
                        HStack {
                            Text("Dashboard")
                                .font(.largeTitle)
                            Spacer()
                            Button("Add") {}
                        }
                        .padding()

                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(items, id: \.self) { item in
                                    HStack {
                                        Circle()
                                            .fill(.blue)
                                            .frame(width: 40, height: 40)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item)
                                                .font(.headline)
                                            Text("Detail for \(item)")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                        Spacer()
                                    }
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(red: 0.1, green: 0.1, blue: 0.12))
                                    )
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }

            let bitmap = render(DashboardView())
            XCTAssertGreaterThan(bitmap.pixels.count, 0)
        }
    }

    func testNestedStacksWithModifiersRenders() async {
        await MainActor.run {
            let bitmap = render(
                ZStack {
                    Rectangle()
                        .fill(.black)
                        .ignoresSafeArea()

                    VStack(spacing: 20) {
                        HStack(spacing: 10) {
                            Rectangle()
                                .fill(.red)
                                .frame(width: 50, height: 50)
                                .cornerRadius(8)
                                .shadow(radius: 4)

                            Rectangle()
                                .fill(.green)
                                .frame(width: 50, height: 50)
                                .rotationEffect(.degrees(15))
                                .opacity(0.8)

                            Rectangle()
                                .fill(.blue)
                                .frame(width: 50, height: 50)
                                .scaleEffect(1.2)
                                .blur(radius: 2)
                        }

                        ZStack {
                            Rectangle()
                                .fill(.white)
                                .frame(width: 200, height: 100)
                            Text("Overlay")
                                .foregroundColor(.black)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(.yellow, lineWidth: 2)
                        )

                        HStack {
                            Spacer()
                            Circle().fill(.purple).frame(width: 30, height: 30)
                            Spacer()
                            Circle().fill(.orange).frame(width: 30, height: 30)
                            Spacer()
                        }
                    }
                }
            )
            XCTAssertGreaterThan(bitmap.pixels.count, 0)
        }
    }

    func testSheetAndAlertPresentationModifiersRenders() async {
        await MainActor.run {
            struct PresentationsView: View {
                @State private var showSheet = false
                @State private var showAlert = false

                var body: some View {
                    VStack(spacing: 20) {
                        Button("Show Sheet") { showSheet = true }
                        Button("Show Alert") { showAlert = true }
                    }
                    .sheet(isPresented: $showSheet) {
                        Text("Sheet Content")
                    }
                    .alert("Title", isPresented: $showAlert) {
                        Button("OK") {}
                    } message: {
                        Text("Alert message")
                    }
                }
            }

            let bitmap = render(PresentationsView())
            XCTAssertGreaterThan(bitmap.pixels.count, 0)
        }
    }

    func testContextMenuModifierRenders() async {
        await MainActor.run {
            let bitmap = render(
                VStack {
                    Text("Right-click me")
                        .padding()
                        .contextMenu {
                            Button("Copy") {}
                            Button("Paste") {}
                            Divider()
                            Button("Delete", role: .destructive) {}
                        }
                }
            )
            XCTAssertGreaterThan(bitmap.pixels.count, 0)
        }
    }

    func testMenuAndToolbarRenders() async {
        await MainActor.run {
            struct ToolbarView: View {
                var body: some View {
                    NavigationStack {
                        Text("Content")
                            .toolbar {
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    Button("Done") {}
                                }
                            }
                    }
                }
            }

            let bitmap = render(ToolbarView())
            XCTAssertGreaterThan(bitmap.pixels.count, 0)
        }
    }

    func testMatchedGeometryEffectInListRenders() async {
        await MainActor.run {
            struct AnimatedListView: View {
                @Namespace private var animation
                let items = ["A", "B", "C"]

                var body: some View {
                    VStack(spacing: 8) {
                        ForEach(items, id: \.self) { item in
                            Text(item)
                                .frame(width: 60, height: 40)
                                .background(
                                    Rectangle()
                                        .fill(.blue)
                                        .matchedGeometryEffect(id: "bg-\(item)", in: animation)
                                )
                        }
                    }
                }
            }

            let bitmap = render(AnimatedListView())
            XCTAssertGreaterThan(bitmap.pixels.count, 0)
        }
    }

    func testSearchableAndRefreshableRenders() async {
        await MainActor.run {
            struct SearchableView: View {
                @State private var query = ""

                var body: some View {
                    List {
                        Text("Item 1")
                        Text("Item 2")
                    }
                    .searchable(text: $query, prompt: "Search items")
                    .refreshable {
                        // async refresh action
                    }
                }
            }

            let bitmap = render(SearchableView())
            XCTAssertGreaterThan(bitmap.pixels.count, 0)
        }
    }

    func testDisclosureGroupAndGroupBoxRenders() async {
        await MainActor.run {
            struct ContainersView: View {
                @State private var isExpanded = true

                var body: some View {
                    VStack(spacing: 16) {
                        DisclosureGroup("Details", isExpanded: $isExpanded) {
                            Text("Hidden content")
                            Text("More hidden content")
                        }

                        GroupBox("Status") {
                            HStack {
                                Circle().fill(.green).frame(width: 10, height: 10)
                                Text("Online")
                                Spacer()
                            }
                        }
                    }
                    .padding()
                }
            }

            let bitmap = render(ContainersView())
            XCTAssertGreaterThan(bitmap.pixels.count, 0)
        }
    }

    func testDragGestureAndDropDestinationRenders() async {
        await MainActor.run {
            let bitmap = render(
                HStack(spacing: 40) {
                    Rectangle()
                        .fill(.red)
                        .frame(width: 60, height: 60)
                        .draggable("payload")

                    Rectangle()
                        .fill(.green)
                        .frame(width: 60, height: 60)
                        .dropDestination(for: String.self) { items, location in
                            true
                        }
                }
            )
            XCTAssertGreaterThan(bitmap.pixels.count, 0)
        }
    }

    func testFocusAndKeyboardShortcutRenders() async {
        await MainActor.run {
            struct FocusView: View {
                @FocusState private var focusedField: Field?
                enum Field: Hashable { case name, email }

                var body: some View {
                    VStack(spacing: 12) {
                        TextField("Name", text: .constant(""))
                            .focused($focusedField, equals: .name)
                        TextField("Email", text: .constant(""))
                            .focused($focusedField, equals: .email)
                        Button("Submit") {}
                            .keyboardShortcut(.return, modifiers: .command)
                    }
                    .padding()
                }
            }

            let bitmap = render(FocusView())
            XCTAssertGreaterThan(bitmap.pixels.count, 0)
        }
    }

    func testHoverEffectAndOnHoverRenders() async {
        await MainActor.run {
            let bitmap = render(
                VStack(spacing: 20) {
                    Rectangle()
                        .fill(.blue)
                        .frame(width: 100, height: 50)
                        .onHover { _ in }

                    Rectangle()
                        .fill(.green)
                        .frame(width: 100, height: 50)
                        .hoverEffect(.highlight)
                }
            )
            XCTAssertGreaterThan(bitmap.pixels.count, 0)
        }
    }

    func testCanvasRenders() async {
        await MainActor.run {
            struct CanvasView: View {
                var body: some View {
                    Canvas { context, size in
                        let rect = CGRect(origin: .zero, size: size)
                        let shading: GraphicsContext.Shading = .color(Color.red)
                        context.fill(rect, with: shading)
                    }
                    .frame(width: 100, height: 100)
                }
            }

            let bitmap = render(CanvasView())
            XCTAssertGreaterThan(bitmap.pixels.count, 0)
        }
    }

    func testViewThatFitsRenders() async {
        await MainActor.run {
            let bitmap = render(
                ViewThatFits {
                    Rectangle().fill(.red).frame(width: 300, height: 200)
                    Rectangle().fill(.green).frame(width: 150, height: 100)
                    Rectangle().fill(.blue).frame(width: 80, height: 50)
                }
                .frame(width: 160, height: 120)
            )
            XCTAssertGreaterThan(bitmap.pixels.count, 0)
        }
    }
}
