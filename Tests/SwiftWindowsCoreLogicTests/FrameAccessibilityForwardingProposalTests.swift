import CUIAInterop
import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Private acceptance proposal; existing APIs only, no native window.
/// Not compiled or run. Required forwarding is absent at f56d1b3.
@MainActor
final class FrameAccessibilityForwardingProposalTests: XCTestCase {
    func testFixedFrameLabelNamesOnlyTheDeclaredImage() async throws {
        let host = FrameAXHost {
            AnyView(
                Image(bitmap: frameAXBitmap()).resizable().frame(width: 48, height: 32)
                    .accessibilityLabel("Exact image").accessibilityIdentifier("subject"))
        }
        defer { host.close() }
        host.render()
        let value = try host.snapshot()
        XCTAssertEqual(value.controlType, Int32(SWU_UIA_CONTROL_TYPE_IMAGE))
        XCTAssertEqual(value.name, "Exact image")
        XCTAssertEqual(host.snapshots.filter { $0.controlType == Int32(SWU_UIA_CONTROL_TYPE_IMAGE) }.count, 1)
        XCTAssertFalse(value.hasDefaultAction)
        XCTAssertFalse(value.supportsValue)
        let frame = try host.frame()
        let child = try XCTUnwrap(frame.children.first)
        XCTAssertTrue(child.parent === frame)
        XCTAssertTrue(child.accessibilityTraits.contains(.isImage))
        XCTAssertNil(frame.selectedContentRole)
        XCTAssertEqual(frame.preferredSize, Size(width: 48, height: 32))
    }

    func testFrameOverloadsPreserveTheUnlabelledGeometry() async throws {
        let variants: [(String, @MainActor (AnyView) -> AnyView)] = [
            ("fixed", { AnyView($0.frame(width: 48, height: 32, alignment: .bottomTrailing)) }),
            ("alignment", { AnyView($0.frame(alignment: .topLeading)) }),
            ("ideal", { AnyView($0.frame(idealWidth: 48, idealHeight: 32, alignment: .leading)) }),
            (
                "flexible",
                {
                    AnyView(
                        $0.frame(
                            minWidth: 20, idealWidth: 48, maxWidth: 80,
                            minHeight: 12, idealHeight: 32, maxHeight: 64, alignment: .bottom))
                }
            ),
            ("rect", { AnyView($0.frame(CGRect(x: 9, y: 11, width: 48, height: 32))) }),
        ]
        for (name, wrap) in variants {
            let base = FrameAXHost { wrap(AnyView(Image(bitmap: frameAXBitmap()).resizable())) }
            let changed = FrameAXHost {
                AnyView(
                    wrap(AnyView(Image(bitmap: frameAXBitmap()).resizable()))
                        .accessibilityLabel(name).accessibilityIdentifier("subject"))
            }
            defer {
                base.close()
                changed.close()
            }
            base.render()
            changed.render()
            let original = try XCTUnwrap(base.projections.first { $0.controlType == .image })
            let result = try changed.projection()
            XCTAssertEqual(result.name, name)
            XCTAssertEqual(result.controlType, .image)
            XCTAssertEqual(result.bounds, original.bounds, name)
            XCTAssertEqual(
                frameAXNodes(base.runtime.root).map(\.resolvedFrame),
                frameAXNodes(changed.runtime.root).map(\.resolvedFrame), name)
        }
    }

    func testNestedEmptyAndFalseOverridesRemainExplicit() async throws {
        let host = FrameAXHost {
            AnyView(
                Image(bitmap: frameAXBitmap()).accessibilityLabel("Base").accessibilityHint("Base hint")
                    .frame(width: 40, height: 30).accessibilityLabel("Inner").accessibilityHint("Inner hint")
                    .accessibilityRespondsToUserInteraction(true).frame(width: 80, height: 60)
                    .accessibilityLabel("").accessibilityHint("").accessibilityRespondsToUserInteraction(false)
                    .accessibilityIdentifier("subject"))
        }
        defer { host.close() }
        host.render()
        let value = try host.snapshot()
        XCTAssertEqual(value.name, "")
        XCTAssertEqual(value.helpText, "")
        XCTAssertFalse(value.isEnabled)
        XCTAssertEqual(value.controlType, Int32(SWU_UIA_CONTROL_TYPE_IMAGE))
        XCTAssertFalse(host.source.uiaSetFocusResult(elementID: value.id))
    }

    func testSameChainFalseAndTrueCannotOverrideIndependentPhysicalAncestors() async throws {
        let model = FrameAXModel()
        let host = FrameAXHost {
            AnyView(
                Button("Base") { model.activations += 1 }.accessibilityHidden(true)
                    .accessibilityRespondsToUserInteraction(false).frame(width: 80, height: 30)
                    .accessibilityHidden(false).accessibilityRespondsToUserInteraction(true)
                    .accessibilityIdentifier("subject"))
        }
        defer { host.close() }
        host.render()
        let id = try host.snapshot().id
        XCTAssertTrue(try host.snapshot().isEnabled)
        XCTAssertTrue(host.source.uiaInvokeDefaultAction(elementID: id))
        host.runtime.root.isHidden = true
        XCTAssertFalse(host.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertFalse(host.snapshots.contains { $0.automationID == "subject" })
        host.runtime.root.isHidden = false
        host.runtime.root.accessibilityRespondsToUserInteraction = false
        XCTAssertFalse(try host.snapshot().isEnabled)
        XCTAssertFalse(host.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertEqual(model.activations, 1)
    }

    func testOrderedTraitEditsApplyToContentDefaults() async throws {
        let first = FrameAXHost {
            AnyView(
                Image(bitmap: frameAXBitmap()).frame(width: 40, height: 30)
                    .accessibilityRemoveTraits(.isImage).accessibilityAddTraits(.isButton)
                    .frame(width: 60, height: 40).accessibilityRemoveTraits(.isButton)
                    .accessibilityAddTraits(.isImage).accessibilityIdentifier("subject"))
        }
        let second = FrameAXHost {
            AnyView(
                Image(bitmap: frameAXBitmap()).frame(width: 40, height: 30)
                    .accessibilityAddTraits(.isButton).accessibilityRemoveTraits(.isButton)
                    .accessibilityRemoveTraits(.isImage).accessibilityIdentifier("subject"))
        }
        defer {
            first.close()
            second.close()
        }
        first.render()
        second.render()
        XCTAssertEqual(try first.projection().traits, .isImage)
        XCTAssertEqual(try first.projection().controlType, .image)
        XCTAssertTrue(try second.projection().traits.isEmpty)
        XCTAssertEqual(try second.projection().controlType, .group)
        XCTAssertFalse(try first.snapshot().hasDefaultAction)
    }

    func testExplicitChildPoliciesKeepTheAuthoredGroupBoundary() async throws {
        for policy in [AccessibilityChildBehavior.ignore, .combine, .contain] {
            let host = FrameAXHost {
                AnyView(
                    Image(bitmap: frameAXBitmap()).accessibilityLabel("Child")
                        .frame(width: 40, height: 30).accessibilityElement(children: policy)
                        .accessibilityLabel("Authored group").accessibilityIdentifier("subject"))
            }
            defer { host.close() }
            host.render()
            let group = try host.snapshot()
            XCTAssertEqual(group.controlType, Int32(SWU_UIA_CONTROL_TYPE_GROUP))
            XCTAssertEqual(group.name, "Authored group")
            XCTAssertEqual(host.descendants.count, policy == .contain ? 2 : 1)
            XCTAssertEqual(
                host.descendants.filter { $0.controlType == Int32(SWU_UIA_CONTROL_TYPE_IMAGE) }.count,
                policy == .contain ? 1 : 0)
            XCTAssertFalse(group.hasDefaultAction)
            XCTAssertFalse(group.supportsItemContainer)
        }
    }

    func testRepresentationDoesNotBorrowThePhysicalChildCapability() async throws {
        let model = FrameAXModel()
        let host = FrameAXHost {
            AnyView(
                Button("Physical") { model.activations += 1 }.frame(width: 100, height: 40)
                    .accessibilityLabel("Owner").accessibilityIdentifier("subject")
                    .accessibilityRepresentation { Text("Replacement text") })
        }
        defer { host.close() }
        host.render()
        let owner = try host.snapshot()
        XCTAssertEqual(owner.controlType, Int32(SWU_UIA_CONTROL_TYPE_GROUP))
        XCTAssertFalse(owner.hasDefaultAction)
        XCTAssertFalse(host.source.uiaInvokeDefaultAction(elementID: owner.id))
        XCTAssertEqual(model.activations, 0)
        XCTAssertFalse(host.descendants.contains { $0.name == "Physical" })
        XCTAssertEqual(host.descendants.filter { $0.name == "Replacement text" }.count, 1)
    }

    func testDeclaredContainerNeverBorrowsDescendantCapabilities() async throws {
        let model = FrameAXModel()
        let host = FrameAXHost {
            AnyView(
                VStack {
                    Button("First") { model.activations += 1 }
                    TextField("Second", text: model.textBinding)
                }.frame(width: 140, height: 80).accessibilityLabel("Container").accessibilityIdentifier("subject"))
        }
        defer { host.close() }
        host.render()
        let value = try host.snapshot()
        XCTAssertEqual(value.controlType, Int32(SWU_UIA_CONTROL_TYPE_GROUP))
        XCTAssertFalse(value.hasDefaultAction)
        XCTAssertFalse(value.supportsValue)
        XCTAssertFalse(value.supportsItemContainer)
        XCTAssertFalse(host.source.uiaInvokeDefaultAction(elementID: value.id))
        XCTAssertFalse(host.source.uiaSetFocusResult(elementID: value.id))
        XCTAssertFalse(host.source.uiaSetValue(elementID: value.id, value: "borrowed"))
        XCTAssertEqual(model.activations, 0)
        XCTAssertTrue(model.writes.isEmpty)
    }

    func testPhysicalTransformScrollClipAndVisibilityArePreserved() async throws {
        let plain = FrameAXHost {
            AnyView(
                ScrollView {
                    Image(bitmap: frameAXBitmap()).resizable()
                        .frame(width: 48, height: 32, alignment: .bottomTrailing)
                        .frame(width: 100, height: 90).offset(x: 7, y: 13).scaleEffect(1.25)
                }
                .frame(width: 110, height: 70).clipped())
        }
        let labelled = FrameAXHost {
            AnyView(
                ScrollView {
                    Image(bitmap: frameAXBitmap()).resizable()
                        .frame(width: 48, height: 32, alignment: .bottomTrailing)
                        .frame(width: 100, height: 90).offset(x: 7, y: 13).scaleEffect(1.25)
                        .accessibilityLabel("Image").accessibilityIdentifier("subject")
                }
                .frame(width: 110, height: 70).clipped())
        }
        defer {
            plain.close()
            labelled.close()
        }
        plain.render()
        labelled.render()
        let plainScroll = try XCTUnwrap(frameAXNodes(plain.runtime.root).first { $0.scrollAxis != nil })
        let labelledScroll = try XCTUnwrap(frameAXNodes(labelled.runtime.root).first { $0.scrollAxis != nil })
        plainScroll.scrollOffset = 12
        labelledScroll.scrollOffset = 12
        plain.render()
        labelled.render()
        XCTAssertEqual(plainScroll.resolvedScrollOffset, 12)
        XCTAssertEqual(labelledScroll.resolvedScrollOffset, 12)
        let expected = try XCTUnwrap(plain.projections.first { $0.controlType == .image })
        let actual = try labelled.projection()
        XCTAssertEqual(actual.bounds, expected.bounds)
        let before = frameAXNodes(plain.runtime.root)
        let after = frameAXNodes(labelled.runtime.root)
        XCTAssertEqual(before.map(\.resolvedFrame), after.map(\.resolvedFrame))
        XCTAssertEqual(before.map(\.clipsToBounds), after.map(\.clipsToBounds))
        XCTAssertEqual(before.map(\.resolvedScrollOffset), after.map(\.resolvedScrollOffset))
        XCTAssertEqual(before.map(\.selectedContentRole), after.map(\.selectedContentRole))
        // No newly intersected ancestor clips or clipping-parity claim.
        let ancestor = try XCTUnwrap(actual.sourceNode?.parent)
        ancestor.isHidden = true
        XCTAssertFalse(labelled.snapshots.contains { $0.automationID == "subject" })
    }

    func testModifierRemovalRestoresBaseOnTheSameRetainedChild() async throws {
        let model = FrameAXModel()
        let host = FrameAXHost {
            let base = Image(bitmap: frameAXBitmap()).accessibilityLabel("Base")
                .accessibilityHint("Base hint").frame(width: 50, height: 30)
            if model.overrides {
                return AnyView(
                    base.accessibilityLabel("Outer").accessibilityHint("")
                        .accessibilityAddTraits(.isButton).accessibilityIdentifier("subject"))
            }
            return AnyView(base.opacity(1).opacity(1).opacity(1).accessibilityIdentifier("subject"))
        }
        defer { host.close() }
        host.render()
        let wrapper = try host.frame()
        let child = try XCTUnwrap(wrapper.children.first)
        let id = try host.snapshot().id
        XCTAssertEqual(try host.snapshot().name, "Outer")
        model.overrides = false
        host.reload()
        host.render()
        XCTAssertTrue(try host.frame() === wrapper)
        XCTAssertTrue(wrapper.children.first === child)
        XCTAssertEqual(child.accessibilityLabel, "Base")
        XCTAssertEqual(child.accessibilityHint, "Base hint")
        XCTAssertEqual(try host.projection().name, "Base")
        XCTAssertEqual(try host.projection().hint, "Base hint")
        XCTAssertEqual(try host.projection().traits, .isImage)
        XCTAssertEqual(try host.snapshot().id, id)
    }

    func testAcceptedAdoptionBindsTheRetainedChildNotTheCandidate() async throws {
        let runtime = frameAXRuntime()
        defer { frameAXClose(runtime) }
        let model = FrameAXModel()
        let first = frameAXNode(
            Button("First") { model.activations += 1 }
                .frame(width: 100, height: 30).accessibilityIdentifier("subject"), in: runtime)
        runtime.root.addChild(first)
        _ = runtime.renderFrame()
        let retained = try XCTUnwrap(first.children.first)
        weak var discarded: ViewNode?
        @inline(never)
        func adoptFresh() throws {
            let candidate = frameAXNode(
                Button("Updated") { model.alternateActivations += 1 }
                    .frame(width: 100, height: 30).accessibilityIdentifier("subject"), in: runtime)
            discarded = try XCTUnwrap(candidate.children.first)
            XCTAssertTrue(discarded !== retained)
            XCTAssertTrue(ComponentHost.adopt(source: candidate, into: first).completed)
            XCTAssertTrue(first.children.first === retained)
        }
        try adoptFresh()
        XCTAssertNil(discarded, "The semantic binding must not retain the discarded source child")
        let source = RuntimeUIAElementTreeSource(runtime: runtime)
        XCTAssertTrue(source.uiaInvokeDefaultAction(elementID: try frameAXSnapshot(source).id))
        XCTAssertEqual(model.activations, 0)
        XCTAssertEqual(model.alternateActivations, 1)
    }

    func testSavedProviderAndProjectionRejectReplacementAndABA() async throws {
        let model = FrameAXModel()
        let host = FrameAXHost {
            let identity = model.identity
            return AnyView(
                Button("Same name") {
                    if identity == 0 { model.activations += 1 } else { model.alternateActivations += 1 }
                }.id(identity).frame(width: 100, height: 30).accessibilityIdentifier("subject"))
        }
        defer { host.close() }
        host.render()
        let wrapper = try host.frame()
        let child = try XCTUnwrap(wrapper.children.first)
        let id = try host.snapshot().id
        let saved = try host.projection()
        model.identity = 1
        host.reload()
        host.render()
        XCTAssertTrue(try host.frame() === wrapper)
        XCTAssertTrue(wrapper.children.first !== child)
        let replacement = try host.snapshot().id
        XCTAssertNotEqual(replacement, id)
        XCTAssertFalse(saved.invokeDefaultAction())
        XCTAssertFalse(host.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertFalse(host.source.uiaSetFocusResult(elementID: id))
        XCTAssertTrue(host.source.uiaInvokeDefaultAction(elementID: replacement))
        model.identity = 0
        host.reload()
        host.render()
        XCTAssertNotEqual(try host.snapshot().id, id)
        XCTAssertFalse(saved.invokeDefaultAction())
        XCTAssertFalse(host.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertEqual(model.activations, 0)
        XCTAssertEqual(model.alternateActivations, 1)
    }

    func testDetachTransferAndReturnCannotReviveTheOldBinding() async throws {
        let host = FrameAXHost {
            AnyView(Text("Same text").frame(width: 100, height: 30).accessibilityIdentifier("subject"))
        }
        let other = frameAXRuntime()
        defer {
            host.close()
            frameAXClose(other)
        }
        host.render()
        let wrapper = try host.frame()
        let id = try host.snapshot().id
        let document = try XCTUnwrap(host.source.uiaTextDocument(elementID: id))
        let range = try XCTUnwrap(document.documentRange())
        other.root.addChild(wrapper)
        host.runtime.root.addChild(wrapper)
        XCTAssertTrue(wrapper.parent === host.runtime.root)
        XCTAssertNil(try range.getText())
        XCTAssertNil(host.source.uiaTextDocument(elementID: id))
        host.reload()
        host.render()
        let current = try host.snapshot().id
        XCTAssertNotEqual(current, id)
        XCTAssertEqual(host.source.uiaTextSnapshot(elementID: current)?.text, "Same text")
    }

    func testLayoutReplacementRefusesTheOriginalInvocationWithoutRetry() async throws {
        let model = FrameAXModel()
        let host = FrameAXHost {
            AnyView(
                Button("Original") { model.activations += 1 }.frame(width: 100, height: 30)
                    .accessibilityIdentifier("subject"))
        }
        defer { host.close() }
        host.render()
        let wrapper = try host.frame()
        let saved = try host.projection()
        let child = try XCTUnwrap(wrapper.children.first)
        var replacements = 0
        child.onLayoutWithNode = { [weak wrapper] _, _ in
            guard replacements == 0, let wrapper else { return }
            replacements += 1
            let replacement = ViewNode(text: "Replacement", accessibilityTraits: .isButton)
            replacement.onActivate = { model.alternateActivations += 1 }
            wrapper.setChildren([replacement])
        }
        host.runtime.setRootSize(IntSize(width: 240, height: 140))
        XCTAssertFalse(saved.invokeDefaultAction())
        XCTAssertEqual(replacements, 1)
        XCTAssertEqual(model.activations, 0)
        XCTAssertEqual(model.alternateActivations, 0)
    }

    func testInvokeToggleAndSelectionReachTheActualControl() async throws {
        let model = FrameAXModel()
        let selectable = AccessibilityTraits(rawValue: RetainedAccessibilityTraits.isSelectable.rawValue)
        let button = FrameAXHost {
            AnyView(
                Button("Button") { model.activations += 1 }.frame(width: 100, height: 30)
                    .accessibilityIdentifier("subject"))
        }
        let toggle = FrameAXHost {
            AnyView(
                Toggle("Toggle", isOn: model.toggleBinding).frame(width: 120, height: 32)
                    .accessibilityIdentifier("subject"))
        }
        let selected = FrameAXHost {
            AnyView(
                Button("Selection route") { model.alternateActivations += 1 }
                    .accessibilityAddTraits(selectable).frame(width: 120, height: 32)
                    .accessibilityIdentifier("subject"))
        }
        defer {
            button.close()
            toggle.close()
            selected.close()
        }
        button.render()
        toggle.render()
        selected.render()
        XCTAssertTrue(button.source.uiaInvokeDefaultAction(elementID: try button.snapshot().id))
        XCTAssertEqual(model.activations, 1)
        XCTAssertTrue(toggle.source.uiaToggle(elementID: try toggle.snapshot().id))
        XCTAssertEqual(model.toggleWrites, [true])
        XCTAssertTrue(selected.source.uiaSelect(elementID: try selected.snapshot().id))
        XCTAssertEqual(model.alternateActivations, 1)
        // Selection-intent dispatch only; logical List semantics are separate.
    }

    func testValueAndFocusKeepTheRealEditorController() async throws {
        let model = FrameAXModel()
        let host = FrameAXHost {
            AnyView(
                TextField("Field", text: model.textBinding).frame(width: 160, height: 32)
                    .accessibilityLabel("Framed editor").accessibilityIdentifier("subject"))
        }
        defer { host.close() }
        host.render()
        let editor = try XCTUnwrap(frameAXNodes(host.runtime.root).first { $0.textInputController != nil })
        XCTAssertNotNil(editor.textInputController)
        let frame = try host.frame()
        let value = try host.snapshot()
        XCTAssertEqual(value.controlType, Int32(SWU_UIA_CONTROL_TYPE_EDIT))
        XCTAssertTrue(value.supportsValue)
        XCTAssertFalse(value.isReadOnly)
        XCTAssertNil(frame.textInputController)
        XCTAssertTrue(host.source.uiaSetValue(elementID: value.id, value: "updated"))
        XCTAssertEqual(model.writes, ["updated"])
        XCTAssertEqual(model.text, "updated")
        XCTAssertTrue(host.runtime.focusedNode === editor)
        XCTAssertTrue(frame.children.first === editor)
        let current = try XCTUnwrap(editor.textInputController as? any TextInputAccessibilityValueReplacing)
        XCTAssertTrue(current.hasCurrentAccessibilityValueOwnership)
        XCTAssertEqual(try host.snapshot().id, value.id)
        XCTAssertFalse(frame.isFocused)
    }

    func testFocusReplacementCannotLendTheNewEditorController() async throws {
        let model = FrameAXModel()
        let alternate = FrameAXModel()
        let host = FrameAXHost {
            AnyView(
                TextField("Same", text: model.textBinding).id(0).frame(width: 160, height: 32)
                    .accessibilityIdentifier("subject"))
        }
        defer { host.close() }
        host.render()
        let wrapper = try host.frame()
        let id = try host.snapshot().id
        let editor = try XCTUnwrap(frameAXNodes(wrapper).first { $0.textInputController != nil })
        let controller = try XCTUnwrap(editor.textInputController)
        let sentinel = ViewNode(frame: Rect(x: 0, y: 100, width: 20, height: 20), isFocusable: true)
        host.runtime.root.addChild(sentinel)
        host.runtime.requestFocus(sentinel)
        var replacements = 0
        sentinel.onFocusExit = { [weak wrapper, weak runtime = host.runtime] in
            guard replacements == 0, let wrapper, let runtime else { return }
            replacements += 1
            let fresh = frameAXNode(
                TextField("Same", text: alternate.textBinding).id(1)
                    .frame(width: 160, height: 32).accessibilityIdentifier("subject"), in: runtime)
            XCTAssertTrue(ComponentHost.adopt(source: fresh, into: wrapper).completed)
        }
        XCTAssertFalse(host.source.uiaSetValue(elementID: id, value: "must not dispatch"))
        XCTAssertEqual(replacements, 1)
        XCTAssertTrue(model.writes.isEmpty)
        XCTAssertTrue(alternate.writes.isEmpty)
        let next = try XCTUnwrap(frameAXNodes(wrapper).first { $0.textInputController != nil })
        XCTAssertTrue(next !== editor)
        XCTAssertTrue(next.textInputController !== controller)
        XCTAssertFalse(host.source.uiaSetFocusResult(elementID: id))
        sentinel.onFocusExit = nil
    }

    func testHeldTextKeepsOriginalContentAndFrameBinding() async throws {
        let model = FrameAXModel()
        let host = FrameAXHost {
            let text = Text("e\u{301} emoji \u{1F642}").frame(width: 160, height: 32)
            if model.overrides {
                return AnyView(text.accessibilityLabel("Outer").accessibilityIdentifier("subject"))
            }
            return AnyView(text.opacity(1).accessibilityIdentifier("subject"))
        }
        defer { host.close() }
        host.render()
        let id = try host.snapshot().id
        let document = try XCTUnwrap(host.source.uiaTextDocument(elementID: id))
        let range = try XCTUnwrap(document.documentRange())
        let content = "e\u{301} emoji \u{1F642}"
        XCTAssertEqual(try range.getText(), content)
        let text = try XCTUnwrap(try host.projection().sourceNode)
        text.text = "intermediate"
        text.text = content
        XCTAssertNil(try range.getText())
        let currentDocument = try XCTUnwrap(host.source.uiaTextDocument(elementID: id))
        let currentRange = try XCTUnwrap(currentDocument.documentRange())
        model.overrides = false
        host.reload()
        host.render()
        XCTAssertTrue(try host.projection().sourceNode === text)
        XCTAssertEqual(
            try currentRange.getText(), content,
            "Label-only removal preserves original text and structural authority")
        XCTAssertNil(try range.getText(), "The earlier content ABA remains refused")
        let nextID = try host.snapshot().id
        XCTAssertEqual(nextID, id)
        XCTAssertEqual(host.source.uiaTextSnapshot(elementID: nextID)?.text, content)
        host.reload()
        host.render()
        XCTAssertEqual(try host.snapshot().id, id)
        XCTAssertTrue(try host.projection().sourceNode === text)
        XCTAssertEqual(try currentRange.getText(), content)
        XCTAssertNil(try range.getText())
    }

    func testSecureFrameNeverExposesBackingTextOrWritableCapability() async throws {
        let model = FrameAXModel()
        model.text = "private backing value"
        let host = FrameAXHost {
            AnyView(
                SecureField("Secret", text: model.textBinding).frame(width: 160, height: 32)
                    .accessibilityLabel("Password").accessibilityIdentifier("subject"))
        }
        defer { host.close() }
        host.render()
        let value = try host.snapshot()
        XCTAssertEqual(value.controlType, Int32(SWU_UIA_CONTROL_TYPE_EDIT))
        XCTAssertTrue(value.isPassword)
        XCTAssertFalse(value.supportsValue)
        XCTAssertNotEqual(value.value, model.text)
        let reads = model.reads
        XCTAssertNil(host.source.uiaTextSnapshot(elementID: value.id))
        XCTAssertNil(host.source.uiaTextDocument(elementID: value.id))
        XCTAssertFalse(host.source.uiaSetValue(elementID: value.id, value: "forbidden"))
        XCTAssertEqual(model.reads, reads)
        XCTAssertTrue(model.writes.isEmpty)
    }

    func testDirectFramedRootKeepsWindowZeroSeparateFromSemanticChild() async throws {
        let runtime = frameAXRuntime()
        defer { frameAXClose(runtime) }
        let root = runtime.root
        @inline(never)
        func adoptRoot(_ identity: Int) throws {
            let candidate = frameAXNode(
                Text("Root text").id(identity).frame(width: 160, height: 32)
                    .accessibilityLabel("Semantic child").accessibilityIdentifier("subject"), in: runtime)
            XCTAssertTrue(candidate !== root)
            XCTAssertNil(candidate.selectedContentRole)
            XCTAssertNil(root.selectedContentRole)
            XCTAssertTrue(ComponentHost.adopt(source: candidate, into: root).completed)
        }
        try adoptRoot(0)
        XCTAssertTrue(runtime.root === root)
        XCTAssertTrue(try XCTUnwrap(root.children.first).parent === root)
        _ = runtime.renderFrame()
        let source = RuntimeUIAElementTreeSource(runtime: runtime, windowName: "Window caption")
        let window = try XCTUnwrap(source.uiaElementSnapshots().first { $0.id == 0 })
        let child = try frameAXSnapshot(source)
        XCTAssertEqual(window.controlType, Int32(SWU_UIA_CONTROL_TYPE_PANE))
        XCTAssertEqual(window.name, "Window caption")
        XCTAssertNil(window.value)
        XCTAssertFalse(window.hasDefaultAction)
        XCTAssertFalse(window.supportsValue)
        XCTAssertFalse(window.supportsItemContainer)
        XCTAssertFalse(window.isKeyboardFocusable)
        XCTAssertFalse(window.hasKeyboardFocus)
        XCTAssertNotEqual(child.id, 0)
        XCTAssertEqual(child.parentID, 0)
        XCTAssertEqual(child.controlType, Int32(SWU_UIA_CONTROL_TYPE_TEXT))
        XCTAssertEqual(child.name, "Semantic child")
        XCTAssertEqual(source.uiaElementSnapshots().filter { $0.name == "Window caption" }.count, 1)
        XCTAssertEqual(source.uiaElementSnapshots().filter { $0.name == "Semantic child" }.count, 1)
        XCTAssertEqual(try frameAXSnapshot(source).id, child.id)
        XCTAssertNil(source.uiaTextSnapshot(elementID: 0))
        XCTAssertNil(source.uiaTextDocument(elementID: 0))
        XCTAssertFalse(source.uiaSetFocusResult(elementID: 0))
        XCTAssertEqual(source.uiaTextSnapshot(elementID: child.id)?.text, "Root text")
        let held = try XCTUnwrap(source.uiaTextDocument(elementID: child.id))
        let range = try XCTUnwrap(held.documentRange())
        try adoptRoot(1)
        _ = runtime.renderFrame()
        XCTAssertNotEqual(try frameAXSnapshot(source).id, child.id)
        XCTAssertNil(source.uiaTextDocument(elementID: child.id))
        XCTAssertNil(try range.getText())
        XCTAssertTrue(runtime.root === root)
    }

    func testUnframedAndSelectedRootPoliciesRemainUnchanged() async throws {
        let ordinary = RetainedViewRuntime(root: ViewNode(text: "Ordinary"))
        let selectedText = ViewNode(text: "Selected")
        let boundary = ViewNode.selectedContentBoundary(role: .viewThatFits, child: selectedText)
        let selected = RetainedViewRuntime(root: boundary)
        defer {
            frameAXClose(ordinary)
            frameAXClose(selected)
        }
        let ordinarySource = RuntimeUIAElementTreeSource(runtime: ordinary)
        let selectedSource = RuntimeUIAElementTreeSource(runtime: selected)
        XCTAssertEqual(ordinarySource.uiaTextSnapshot(elementID: 0)?.text, "Ordinary")
        XCTAssertEqual(selectedSource.uiaElementSnapshots().first?.id, 0)
        XCTAssertEqual(selectedSource.uiaElementSnapshots().first?.name, "Selected")
        XCTAssertNil(selectedSource.uiaTextSnapshot(elementID: 0))
        XCTAssertNil(selectedSource.uiaTextDocument(elementID: 0))
    }

    func testFramedListPreservesItsInnerContainerWithoutBorrowingTheAdapter() async throws {
        let model = FrameAXModel()
        let rowContent: (Int) -> AnyView = { index in
            model.factories.append(index)
            return AnyView(
                Button("Row \(index)") { model.rowActivations.append(index) }
                    .frame(height: 24).accessibilityIdentifier("row-\(index)"))
        }
        let host = FrameAXHost(size: Size(width: 220, height: 80)) {
            AnyView(
                List(Array(0..<64), id: \.self) { index in
                    rowContent(index)
                }.listStyle(.plain).frame(width: 220, height: 80)
                    .accessibilityLabel("Framed list").accessibilityIdentifier("subject"))
        }
        defer { host.close() }
        host.render()
        let subject = try host.snapshot()
        XCTAssertFalse(
            subject.supportsItemContainer,
            "Public List returns a scroll root; its inner declared List node owns the adapter")
        let containers = host.snapshots.filter(\.supportsItemContainer)
        XCTAssertEqual(containers.count, 1)
        let container = try XCTUnwrap(containers.first)
        XCTAssertNotEqual(container.id, subject.id)
        let nativeContainers = frameAXNodes(host.runtime.root).filter { $0.retainedLazyListAdapter != nil }
        XCTAssertEqual(nativeContainers.count, 1)
        let factories = model.factories
        var item: UInt64?
        for _ in 0...30 {
            guard case .item(let next) = host.source.uiaFindItem(containerID: container.id, afterElementID: item) else {
                return XCTFail("Expected the original declared List item sequence")
            }
            item = next
        }
        XCTAssertEqual(model.factories, factories, "Enumeration must not realize row bodies")
        let id = try XCTUnwrap(item)
        XCTAssertEqual(host.source.uiaLogicalItemState(elementID: id), .placeholder)
        XCTAssertTrue(host.source.uiaRealizeVirtualizedItem(elementID: id))
        XCTAssertEqual(host.source.uiaLogicalItemState(elementID: id), .ordinary)
        XCTAssertGreaterThan(host.runtime.lastLazyListConsumedRounds, 0)
        XCTAssertLessThanOrEqual(host.runtime.lastLazyListConsumedRounds, 4)
        XCTAssertLessThanOrEqual(host.runtime.lastLazyListConsumedElements, 128)
        XCTAssertTrue(model.rowActivations.isEmpty)
        XCTAssertFalse(host.runtime.hasActiveRetainedBuild)
    }

    func testExplicitActionOwnersPreserveAppendOrderAndChildFallback() async throws {
        let model = FrameAXModel()
        let host = FrameAXHost {
            let base = Button("Control") { model.activations += 1 }
                .accessibilityAction(named: "Inner") { model.actionNames.append("inner") }
                .frame(width: 120, height: 32).accessibilityIdentifier("subject")
            if model.overrides {
                return AnyView(
                    base.accessibilityAction(named: "Outer") { model.actionNames.append("outer") }
                        .accessibilityAction { model.actionNames.append("outer-default") })
            }
            return AnyView(base.opacity(1).opacity(1))
        }
        defer { host.close() }
        host.render()
        let frame = try host.frame()
        let child = try XCTUnwrap(frame.children.first)
        let id = try host.snapshot().id
        let old = try host.projection()
        XCTAssertEqual(old.actions.map(\.name), ["Inner", "Outer", "Activate"])
        try XCTUnwrap(old.actions.first { $0.name == "Inner" }).invoke()
        try XCTUnwrap(old.actions.first { $0.name == "Outer" }).invoke()
        XCTAssertTrue(old.invokeDefaultAction())
        XCTAssertEqual(model.actionNames, ["inner", "outer", "outer-default"])
        XCTAssertEqual(model.activations, 0)
        model.overrides = false
        host.reload()
        host.render()
        XCTAssertFalse(old.invokeDefaultAction())
        let current = try host.projection()
        XCTAssertTrue(try host.frame() === frame)
        XCTAssertTrue(frame.children.first === child)
        XCTAssertEqual(try host.snapshot().id, id)
        XCTAssertEqual(current.actions.map(\.name), ["Inner"])
        XCTAssertTrue(current.invokeDefaultAction())
        XCTAssertEqual(model.actionNames, ["inner", "outer", "outer-default", "inner"])
        XCTAssertEqual(model.activations, 0)
    }

    func testModalTraitOrderChangesRoutingButNotPhysicalChromeModality() async throws {
        let model = FrameAXModel()
        let host = FrameAXHost {
            let base = Button("Modal") {}.accessibilityAddTraits(.isModal).frame(width: 100, height: 30)
            let framed: AnyView
            if model.overrides {
                framed = AnyView(base.accessibilityRemoveTraits(.isModal).accessibilityIdentifier("subject"))
            } else {
                framed = AnyView(base.opacity(1).accessibilityIdentifier("subject"))
            }
            return AnyView(
                VStack {
                    framed
                    Button("Outside") { model.activations += 1 }.accessibilityIdentifier("outside")
                })
        }
        defer { host.close() }
        host.render()
        let outside = try host.snapshot("outside").id
        XCTAssertNil(host.runtime.presentationModalSnapshot)
        XCTAssertFalse(try host.projection().traits.contains(.isModal))
        XCTAssertTrue(host.source.uiaInvokeDefaultAction(elementID: outside))
        model.overrides = false
        host.reload()
        host.render()
        let modal = try XCTUnwrap(host.runtime.presentationModalSnapshot)
        XCTAssertTrue(modal === (try host.projection().sourceNode))
        XCTAssertFalse(host.source.uiaInvokeDefaultAction(elementID: outside))
        model.overrides = true
        host.reload()
        host.render()
        XCTAssertNil(host.runtime.presentationModalSnapshot)
        let frame = try XCTUnwrap(try host.projection().sourceNode?.parent)
        frame.presentationChrome.hasBackgroundInteractionOverride = true
        frame.presentationChrome.allowsBackgroundInteraction = false
        XCTAssertTrue(host.runtime.presentationModalSnapshot === frame)
        XCTAssertFalse(host.source.uiaInvokeDefaultAction(elementID: outside))
        XCTAssertEqual(model.activations, 1)
    }

    func testOuterActionCaptureRetirementCannotReenterAnOldBinding() async throws {
        let runtime = frameAXRuntime()
        defer { frameAXClose(runtime) }
        let source = RuntimeUIAElementTreeSource(runtime: runtime)
        let model = FrameAXModel()
        var oldID: UInt64?
        var releases = 0
        var reentryResults: [Bool] = []
        let original = frameAXNodeWithRetirement(in: runtime, model: model) {
            releases += 1
            if let oldID { reentryResults.append(source.uiaInvokeDefaultAction(elementID: oldID)) }
        }
        runtime.root.addChild(original)
        _ = runtime.renderFrame()
        oldID = try frameAXSnapshot(source).id
        let candidate = frameAXNode(
            Button("Control") { model.activations += 1 }
                .frame(width: 120, height: 32).accessibilityIdentifier("subject").opacity(1), in: runtime)
        let child = try XCTUnwrap(original.children.first)
        XCTAssertTrue(ComponentHost.adopt(source: candidate, into: original).completed)
        XCTAssertEqual(releases, 1)
        XCTAssertEqual(reentryResults, [false])
        XCTAssertEqual(model.activations, 0)
        let current = try frameAXSnapshot(source).id
        XCTAssertEqual(current, oldID)
        XCTAssertTrue(original.children.first === child)
        XCTAssertTrue(source.uiaInvokeDefaultAction(elementID: current))
        XCTAssertEqual(model.activations, 1)
    }

    func testHeldTextRejectsPhysicalPrivacyRepresentationDeferralAndModalBlocking() async throws {
        let changes: [@MainActor (ViewNode, RetainedViewRuntime) -> Void] = [
            { frame, _ in frame.isPrivacySensitive = true },
            { frame, _ in frame.accessibilityRepresentationChildren = [ViewNode(text: "Representation")] },
            { frame, _ in frame.isLayoutDeferredByVirtualization = true },
            { frame, _ in frame.isAccessibilityHidden = true },
            { _, runtime in
                let modal = ViewNode(
                    frame: Rect(x: 0, y: 50, width: 30, height: 30),
                    accessibilityLabel: "Modal", accessibilityTraits: .isModal)
                runtime.root.addChild(modal)
                _ = runtime.renderFrame()
            },
        ]
        for change in changes {
            let host = FrameAXHost {
                AnyView(Text("Original").frame(width: 100, height: 30).accessibilityIdentifier("subject"))
            }
            defer { host.close() }
            host.render()
            let id = try host.snapshot().id
            let document = try XCTUnwrap(host.source.uiaTextDocument(elementID: id))
            let range = try XCTUnwrap(document.documentRange())
            change(try host.frame(), host.runtime)
            XCTAssertNil(try range.getText())
            XCTAssertNil(host.source.uiaTextSnapshot(elementID: id))
            XCTAssertNil(host.source.uiaTextDocument(elementID: id))
        }
    }

    func testRemovingOnlyOuterActionRestoresChildActivationWithoutRefreshingSavedAction() async throws {
        let model = FrameAXModel()
        let host = FrameAXHost {
            let base = Button("Control") { model.activations += 1 }
                .frame(width: 120, height: 32).accessibilityIdentifier("subject")
            if model.overrides {
                return AnyView(base.accessibilityAction { model.alternateActivations += 1 })
            }
            return AnyView(base.opacity(1))
        }
        defer { host.close() }
        host.render()
        let frame = try host.frame()
        let child = try XCTUnwrap(frame.children.first)
        let old = try host.projection()
        let id = try host.snapshot().id
        XCTAssertTrue(old.invokeDefaultAction())
        XCTAssertEqual(model.alternateActivations, 1)
        model.overrides = false
        host.reload()
        host.render()
        XCTAssertTrue(try host.frame() === frame)
        XCTAssertTrue(frame.children.first === child)
        XCTAssertFalse(old.invokeDefaultAction())
        XCTAssertTrue(try host.projection().actions.isEmpty)
        XCTAssertEqual(try host.snapshot().id, id)
        XCTAssertTrue(host.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertEqual(model.activations, 1)
        XCTAssertEqual(model.alternateActivations, 1)
    }

    func testValueSetterReplacementNeverRetriesAgainstTheReplacementController() async throws {
        let model = FrameAXModel()
        let alternate = FrameAXModel()
        let host = FrameAXHost {
            AnyView(
                TextField("Same", text: model.textBinding).id(0).frame(width: 160, height: 32)
                    .accessibilityIdentifier("subject"))
        }
        defer { host.close() }
        host.render()
        let wrapper = try host.frame()
        let id = try host.snapshot().id
        var replacements = 0
        model.afterWrite = { [weak wrapper, weak runtime = host.runtime] in
            guard replacements == 0, let wrapper, let runtime else { return }
            replacements += 1
            let fresh = frameAXNode(
                TextField("Same", text: alternate.textBinding).id(1)
                    .frame(width: 160, height: 32).accessibilityIdentifier("subject"), in: runtime)
            XCTAssertTrue(ComponentHost.adopt(source: fresh, into: wrapper).completed)
        }
        XCTAssertFalse(host.source.uiaSetValue(elementID: id, value: "submitted once"))
        XCTAssertEqual(replacements, 1)
        XCTAssertEqual(model.writes, ["submitted once"])
        XCTAssertTrue(alternate.writes.isEmpty)
        XCTAssertFalse(host.source.uiaSetValue(elementID: id, value: "stale retry"))
        XCTAssertEqual(model.writes, ["submitted once"])
        XCTAssertTrue(alternate.writes.isEmpty)
        model.afterWrite = nil
    }
    func testFailedAdoptionCannotPublishOrLazilyRebuildTheCandidateBinding() async throws {
        let runtime = frameAXRuntime()
        defer { frameAXClose(runtime) }
        let source = RuntimeUIAElementTreeSource(runtime: runtime)
        let model = FrameAXModel()
        weak var frameForRetirement: ViewNode?
        weak var childForRetirement: ViewNode?
        var retirements = 0
        let original = frameAXNodeWithRetirement(in: runtime, model: model) {
            retirements += 1
            guard let frame = frameForRetirement, let child = childForRetirement else { return }
            frame.removeAllChildren()
            frame.addChild(child)
        }
        frameForRetirement = original
        runtime.root.addChild(original)
        _ = runtime.renderFrame()
        childForRetirement = try XCTUnwrap(original.children.first)
        let oldID = try frameAXSnapshot(source).id
        let candidate = frameAXNode(
            Button("Candidate") { model.alternateActivations += 1 }
                .frame(width: 120, height: 32).accessibilityLabel("Candidate overlay")
                .accessibilityIdentifier("subject"), in: runtime)
        let result = ComponentHost.adopt(source: candidate, into: original)
        XCTAssertEqual(retirements, 1, "The callback must actually exercise the checked adoption")
        XCTAssertFalse(result.completed)
        XCTAssertTrue(runtime.permitsRetainedActionInvocation)
        XCTAssertFalse(source.uiaInvokeDefaultAction(elementID: oldID))
        XCTAssertFalse(
            source.uiaElementSnapshots().contains { $0.automationID == "subject" },
            "An unfinished frame declaration cannot acquire a fresh binding through a getter")
        XCTAssertEqual(model.activations, 0)
        XCTAssertEqual(model.alternateActivations, 0)
    }
    func testSameChildLabelChangeAndNoOpRebuildKeepTheElementID() async throws {
        let model = FrameAXModel()
        model.text = "First label"
        let host = FrameAXHost {
            AnyView(
                Button("Control") { model.activations += 1 }.frame(width: 120, height: 32)
                    .accessibilityLabel(model.text).accessibilityIdentifier("subject"))
        }
        defer { host.close() }
        host.render()
        let frame = try host.frame()
        let child = try XCTUnwrap(frame.children.first)
        let original = try host.snapshot()
        let saved = try host.projection()
        XCTAssertEqual(original.name, "First label")
        model.text = "Second label"
        host.reload()
        host.render()
        XCTAssertTrue(try host.frame() === frame)
        XCTAssertTrue(frame.children.first === child)
        XCTAssertEqual(try host.snapshot().id, original.id)
        XCTAssertEqual(try host.snapshot().name, "Second label")
        XCTAssertFalse(saved.invokeDefaultAction(), "A rebuilt handler cannot replace the saved operation's owner")
        XCTAssertTrue(host.source.uiaInvokeDefaultAction(elementID: original.id))
        XCTAssertEqual(model.activations, 1)
        host.reload()
        host.render()
        XCTAssertTrue(try host.frame() === frame)
        XCTAssertTrue(frame.children.first === child)
        XCTAssertEqual(try host.snapshot().id, original.id)
        XCTAssertEqual(try host.snapshot().name, "Second label")
        XCTAssertTrue(host.source.uiaInvokeDefaultAction(elementID: original.id))
        XCTAssertEqual(model.activations, 2)
    }

    func testSameShapeActionABADoesNotRetargetSavedAction() async throws {
        let model = FrameAXModel()
        let host = FrameAXHost {
            AnyView(
                Button("Control") { model.activations += 1 }.frame(width: 120, height: 32)
                    .accessibilityIdentifier("subject")
                    .accessibilityAction(named: "Apply") { model.actionNames.append("A") })
        }
        defer { host.close() }
        host.render()
        let frame = try host.frame()
        let child = try XCTUnwrap(frame.children.first)
        let id = try host.snapshot().id
        let saved = try host.projection()
        let savedAction = try XCTUnwrap(saved.actions.first)
        let originalActions = frame.accessibilityActions
        XCTAssertEqual(originalActions.count, 1)
        XCTAssertEqual(saved.actions.map(\.name), ["Apply"])
        frame.accessibilityActions = [RetainedAccessibilityAction(name: "Apply") { model.actionNames.append("B") }]
        frame.accessibilityActions = originalActions
        XCTAssertEqual(frame.accessibilityActions.count, originalActions.count)
        XCTAssertEqual(frame.accessibilityActions.first?.name, originalActions.first?.name)
        XCTAssertEqual(frame.accessibilityActions.first?.kind, originalActions.first?.kind)
        XCTAssertTrue(frame.children.first === child)
        XCTAssertEqual(try host.snapshot().id, id)
        savedAction.invoke()
        XCTAssertFalse(saved.invokeDefaultAction())
        XCTAssertTrue(model.actionNames.isEmpty)
        XCTAssertEqual(model.activations, 0)
        XCTAssertTrue(host.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertEqual(model.actionNames, ["A"])
        XCTAssertEqual(model.activations, 0)
    }

    func testLayoutActionReplacementRejectsOriginalSlotWithoutRetry() async throws {
        let model = FrameAXModel()
        let host = FrameAXHost {
            AnyView(
                Button("Control") { model.activations += 1 }.frame(width: 120, height: 32)
                    .accessibilityIdentifier("subject")
                    .accessibilityAction(named: "Apply") { model.actionNames.append("A") })
        }
        defer { host.close() }
        host.render()
        let frame = try host.frame()
        let child = try XCTUnwrap(frame.children.first)
        let id = try host.snapshot().id
        let saved = try host.projection()
        let originalActions = frame.accessibilityActions
        var callbacks = 0
        child.onLayoutWithNode = { [weak frame] _, _ in
            guard callbacks == 0, let frame else { return }
            callbacks += 1
            frame.accessibilityActions = [
                RetainedAccessibilityAction(name: "Apply") {
                    model.actionNames.append("B")
                }
            ]
            frame.accessibilityActions = originalActions
        }
        host.runtime.root.frame.size = Size(width: 201, height: 121)
        XCTAssertFalse(saved.invokeDefaultAction())
        XCTAssertEqual(callbacks, 1, "The original query must exercise the mutation boundary")
        XCTAssertTrue(model.actionNames.isEmpty)
        XCTAssertEqual(model.activations, 0)
        child.onLayoutWithNode = nil
        XCTAssertEqual(try host.snapshot().id, id)
        XCTAssertTrue(frame.children.first === child)
        XCTAssertTrue(host.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertEqual(model.actionNames, ["A"])
    }

    func testMaskedSecureEditorKeepsNativeReadProtectionWithoutGetterEffects() async throws {
        for replacesRole in [false, true] {
            let model = FrameAXModel()
            model.text = "private backing value"
            let secureTrait = AccessibilityTraits(rawValue: RetainedAccessibilityTraits.isSecureTextInput.rawValue)
            let masked = replacesRole ? secureTrait.union(.isTextInput) : secureTrait
            let host = FrameAXHost {
                let base = SecureField("Secret", text: model.textBinding).frame(width: 160, height: 32)
                    .accessibilityRemoveTraits(masked).accessibilityLabel("Password")
                    .accessibilityValue("authored private value").accessibilityIdentifier("subject")
                return replacesRole ? AnyView(base.accessibilityAddTraits(.isStaticText)) : AnyView(base.opacity(1))
            }
            defer { host.close() }
            host.render()
            let frame = try host.frame()
            let editor = try XCTUnwrap(frame.children.first)
            let controller = try XCTUnwrap(editor.textInputController)
            let id = try host.snapshot().id
            let sentinel = ViewNode(frame: Rect(x: 0, y: 90, width: 20, height: 20), isFocusable: true)
            host.runtime.root.addChild(sentinel)
            host.runtime.requestFocus(sentinel)
            let reads = model.reads
            for removeBasePresentationTraits in [false, true] {
                if removeBasePresentationTraits {
                    editor.accessibilityTraits.subtract([.isSecureTextInput, .isTextInput])
                    editor.accessibilityTraits.insert(.isStaticText)
                    editor.text = "Do not expose controller-owned text"
                }
                let value = try host.snapshot()
                XCTAssertEqual(value.id, id)
                if replacesRole || removeBasePresentationTraits {
                    XCTAssertEqual(value.controlType, Int32(SWU_UIA_CONTROL_TYPE_TEXT))
                } else {
                    XCTAssertEqual(value.controlType, Int32(SWU_UIA_CONTROL_TYPE_EDIT))
                }
                XCTAssertTrue(value.isPassword, "Presentation traits cannot erase actual secure-editor ownership")
                XCTAssertFalse(value.supportsValue)
                XCTAssertTrue(value.isReadOnly)
                XCTAssertNil(value.value)
                let query = UIAQuerySnapshot(host.snapshots)
                XCTAssertNil(query.stringProperty(id, property: Int32(SWU_UIA_STRING_VALUE)))
                XCTAssertNil(host.source.uiaTextSnapshot(elementID: id))
                XCTAssertNil(host.source.uiaTextDocument(elementID: id))
                XCTAssertFalse(host.source.uiaSetValue(elementID: id, value: "forbidden"))
                XCTAssertTrue(host.runtime.focusedNode === sentinel)
                XCTAssertTrue(editor.textInputController === controller)
                XCTAssertNil(frame.textInputController)
                XCTAssertEqual(model.reads, reads)
                XCTAssertTrue(model.writes.isEmpty)
            }
            XCTAssertTrue(
                host.source.uiaSetFocusResult(elementID: id),
                "Secure input remains focusable even though Text and Value disclosure are refused")
            XCTAssertTrue(host.runtime.focusedNode === editor)
            XCTAssertTrue(model.writes.isEmpty)
        }
    }

    func testFramedButtonRootDoesNotLendItsInvocationToWindowZero() async throws {
        let runtime = frameAXRuntime()
        defer { frameAXClose(runtime) }
        let model = FrameAXModel()
        @inline(never)
        func install() throws {
            let candidate = frameAXNode(
                Button("Control") { model.activations += 1 }
                    .frame(width: 160, height: 32).accessibilityLabel("Semantic child")
                    .accessibilityIdentifier("subject"), in: runtime)
            XCTAssertTrue(ComponentHost.adopt(source: candidate, into: runtime.root).completed)
        }
        try install()
        _ = runtime.renderFrame()
        let source = RuntimeUIAElementTreeSource(runtime: runtime, windowName: "Window caption")
        let window = try XCTUnwrap(source.uiaElementSnapshots().first { $0.id == 0 })
        let child = try frameAXSnapshot(source)
        XCTAssertEqual(window.name, "Window caption")
        XCTAssertEqual(window.controlType, Int32(SWU_UIA_CONTROL_TYPE_PANE))
        XCTAssertFalse(window.hasDefaultAction)
        XCTAssertFalse(window.isKeyboardFocusable)
        XCTAssertEqual(child.name, "Semantic child")
        XCTAssertNotEqual(child.id, 0)
        XCTAssertEqual(child.parentID, 0)
        XCTAssertTrue(child.hasDefaultAction)
        XCTAssertEqual(source.uiaElementSnapshots().filter { $0.name == "Semantic child" }.count, 1)
        XCTAssertFalse(source.uiaInvokeDefaultAction(elementID: 0))
        XCTAssertFalse(source.uiaSetFocusResult(elementID: 0))
        XCTAssertEqual(model.activations, 0)
        XCTAssertTrue(source.uiaInvokeDefaultAction(elementID: child.id))
        XCTAssertEqual(model.activations, 1)
    }

    func testFramedEditorRootDoesNotLendValueOrFocusToWindowZero() async throws {
        let runtime = frameAXRuntime()
        defer { frameAXClose(runtime) }
        let model = FrameAXModel()
        @inline(never)
        func install() throws {
            let candidate = frameAXNode(
                TextField("Field", text: model.textBinding)
                    .frame(width: 160, height: 32).accessibilityLabel("Semantic child")
                    .accessibilityIdentifier("subject"), in: runtime)
            XCTAssertTrue(ComponentHost.adopt(source: candidate, into: runtime.root).completed)
        }
        try install()
        _ = runtime.renderFrame()
        let source = RuntimeUIAElementTreeSource(runtime: runtime, windowName: "Window caption")
        let window = try XCTUnwrap(source.uiaElementSnapshots().first { $0.id == 0 })
        let child = try frameAXSnapshot(source)
        let editor = try XCTUnwrap(runtime.root.children.first)
        XCTAssertNotNil(editor.textInputController)
        XCTAssertNil(runtime.root.textInputController)
        XCTAssertEqual(window.name, "Window caption")
        XCTAssertNil(window.value)
        XCTAssertFalse(window.supportsValue)
        XCTAssertFalse(window.isKeyboardFocusable)
        XCTAssertEqual(child.name, "Semantic child")
        XCTAssertNotEqual(child.id, 0)
        XCTAssertEqual(child.parentID, 0)
        XCTAssertTrue(child.supportsValue)
        XCTAssertTrue(child.isKeyboardFocusable)
        let reads = model.reads
        XCTAssertFalse(source.uiaSetValue(elementID: 0, value: "forbidden"))
        XCTAssertFalse(source.uiaSetFocusResult(elementID: 0))
        XCTAssertEqual(model.reads, reads)
        XCTAssertTrue(model.writes.isEmpty)
        XCTAssertFalse(runtime.focusedNode === editor)
        XCTAssertTrue(source.uiaSetFocusResult(elementID: child.id))
        XCTAssertTrue(runtime.focusedNode === editor)
        XCTAssertTrue(source.uiaSetValue(elementID: child.id, value: "accepted"))
        XCTAssertEqual(model.writes, ["accepted"])
        XCTAssertTrue(runtime.focusedNode === editor)
        XCTAssertEqual(try frameAXSnapshot(source).id, child.id)
        XCTAssertFalse(try XCTUnwrap(source.uiaElementSnapshots().first { $0.id == 0 }).hasKeyboardFocus)
    }

    func testFramedNativeAdapterRootKeepsItemContainerOffWindowZero() async throws {
        let runtime = frameAXRuntime()
        let rows = RetainedLazyListDataSource<Int, [ViewNode]>()
        defer {
            frameAXClose(runtime)
            rows.close()
        }
        let identity = RetainedViewIdentity(segments: [.role(.content), .slot(0)])
        XCTAssertTrue(
            rows.replaceData([0, 1], id: \.self, identityRoot: identity) { value, prefix in
                let row = ViewNode(text: "Row \(value)", preferredSize: Size(width: 160, height: 20))
                row.retainedViewIdentity = prefix.appending(.slot(0)).appending(.role(.row))
                row.dynamicContentIndex = value
                return [row]
            })
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: rows, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 4, maximumMountedLeaves: 4, maximumProtectedRecords: 1))
        @inline(never)
        func install() throws {
            let candidate = frameAXNode(
                FrameAXNativeList(adapter: adapter, identity: identity)
                    .frame(width: 160, height: 80).accessibilityLabel("Semantic list")
                    .accessibilityIdentifier("subject"), in: runtime)
            // The frame is the physical viewport; only its declared content owns
            // an adapter. This is native test content, not public List's scroll root.
            candidate.scrollAxis = .vertical
            candidate.clipsToBounds = true
            XCTAssertTrue(ComponentHost.adopt(source: candidate, into: runtime.root).completed)
        }
        try install()
        runtime.root.frame.size = Size(width: 160, height: 80)
        _ = runtime.renderFrame()
        let source = RuntimeUIAElementTreeSource(runtime: runtime, windowName: "Window caption")
        let window = try XCTUnwrap(source.uiaElementSnapshots().first { $0.id == 0 })
        let content = try XCTUnwrap(runtime.root.children.first)
        let child = try frameAXSnapshot(source)
        XCTAssertNil(runtime.root.retainedLazyListAdapter)
        XCTAssertTrue(content.retainedLazyListAdapter === adapter)
        XCTAssertEqual(content.scrollAxis, nil)
        XCTAssertEqual(runtime.root.scrollAxis, .vertical)
        XCTAssertEqual(window.name, "Window caption")
        XCTAssertFalse(window.supportsItemContainer)
        XCTAssertEqual(child.name, "Semantic list")
        XCTAssertNotEqual(child.id, 0)
        XCTAssertEqual(child.parentID, 0)
        XCTAssertTrue(child.supportsItemContainer)
        XCTAssertEqual(source.uiaFindItem(containerID: 0, afterElementID: nil), .unavailable)
        guard case .item(let first) = source.uiaFindItem(containerID: child.id, afterElementID: nil) else {
            return XCTFail("The declared adapter child must retain its real ItemContainer capability")
        }
        guard case .item(let second) = source.uiaFindItem(containerID: child.id, afterElementID: first) else {
            return XCTFail("The original logical item sequence must remain available")
        }
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try frameAXSnapshot(source).id, child.id)
    }

}

@MainActor
private final class FrameAXModel {
    var text = "base"
    var reads = 0
    var writes: [String] = []
    var afterWrite: (() -> Void)?
    var activations = 0
    var alternateActivations = 0
    var overrides = true
    var identity = 0
    var toggle = false
    var toggleWrites: [Bool] = []
    var actionNames: [String] = []
    var factories: [Int] = []
    var rowActivations: [Int] = []
    var textBinding: Binding<String> {
        Binding(
            get: {
                self.reads += 1
                return self.text
            },
            set: {
                self.writes.append($0)
                self.text = $0
                self.afterWrite?()
            })
    }
    var toggleBinding: Binding<Bool> {
        Binding(
            get: { self.toggle },
            set: {
                self.toggleWrites.append($0)
                self.toggle = $0
            })
    }
}

@MainActor
private final class FrameAXHost {
    let runtime: RetainedViewRuntime
    let componentHost: ComponentHost
    let coordinator: StateMountCoordinator
    let source: RuntimeUIAElementTreeSource
    private var isClosed = false

    init(size: Size = Size(width: 200, height: 120), content: @escaping @MainActor () -> AnyView) {
        let runtime = RetainedViewRuntime(
            root: ViewNode(frame: Rect(x: 0, y: 0, width: size.width, height: size.height)))
        let host = ComponentHost(runtime: runtime)
        let coordinator = StateMountCoordinator(
            invalidate: { [weak host] in host?.reload() },
            observeObject: { _ in }, updateObservedObjects: { _, _, _ in })
        self.runtime = runtime
        self.componentHost = host
        self.coordinator = coordinator
        self.source = RuntimeUIAElementTreeSource(runtime: runtime)
        host.buildLifecycle = coordinator
        host.shouldUpdate = { [weak self] in self?.isClosed == false }
        let context = ViewBuildContext(
            stateMountCoordinator: coordinator, canvasSizeProvider: { size },
            invalidateHandler: { [weak host] in host?.reload() })
        host.setComponents { [weak self] in
            guard self?.isClosed == false else { return [] }
            return [makeViewComponent(content(), context: context)]
        }
    }
    var snapshots: [UIAElementSnapshot] { source.uiaElementSnapshots() }
    var descendants: [UIAElementSnapshot] { snapshots.filter { $0.id != 0 } }
    var projections: [AccessibilityElementProjection] {
        AccessibilityProjection.project(runtime: runtime)?.flattened() ?? []
    }
    func render() { if !isClosed { _ = runtime.renderScene() } }
    func reload() { if !isClosed { componentHost.reload() } }
    func frame() throws -> ViewNode { try XCTUnwrap(runtime.root.children.first) }
    func snapshot(_ identifier: String = "subject") throws -> UIAElementSnapshot {
        try frameAXSnapshot(source, identifier)
    }
    func projection(_ identifier: String = "subject") throws -> AccessibilityElementProjection {
        let matches = projections.filter { $0.identifier == identifier }
        XCTAssertEqual(matches.count, 1, identifier)
        return try XCTUnwrap(matches.first)
    }
    func close() {
        guard !isClosed else { return }
        isClosed = true
        runtime.stopRenderLifecycleCallbacks()
        coordinator.close()
        componentHost.onReloadCompleted = nil
        componentHost.setComponents { [] }
        runtime.cancelRenderLifecycleTasks()
        runtime.root.removeAllChildren()
    }
}

@MainActor
private func frameAXNode<Content: View>(_ content: Content, in runtime: RetainedViewRuntime) -> ViewNode {
    let context = ViewBuildContext(canvasSizeProvider: { Size(width: 200, height: 120) }, invalidateHandler: {})
    return content.makeComponent(context: context).makeNode(runtime: runtime)
}

@MainActor
private func frameAXRuntime() -> RetainedViewRuntime {
    RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 120)))
}

@MainActor
private func frameAXClose(_ runtime: RetainedViewRuntime) {
    runtime.stopRenderLifecycleCallbacks()
    runtime.cancelRenderLifecycleTasks()
    runtime.root.removeAllChildren()
}

@MainActor
private func frameAXSnapshot(_ source: RuntimeUIAElementTreeSource, _ identifier: String = "subject") throws
    -> UIAElementSnapshot
{
    let matches = source.uiaElementSnapshots().filter { $0.automationID == identifier }
    XCTAssertEqual(matches.count, 1, identifier)
    return try XCTUnwrap(matches.first)
}

@MainActor
private func frameAXNodes(_ root: ViewNode) -> [ViewNode] {
    var nodes: [ViewNode] = []
    var pending = [root]
    while let node = pending.popLast() {
        nodes.append(node)
        pending.append(contentsOf: node.children.reversed())
    }
    return nodes
}

private func frameAXBitmap() -> BitmapSurface {
    BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([0, 255, 0, 255]))
}

@MainActor
private final class FrameAXRetirement {
    let body: @MainActor () -> Void
    init(_ body: @escaping @MainActor () -> Void) { self.body = body }
    deinit { MainActor.assumeIsolated { body() } }
}

@MainActor
@inline(never)
private func frameAXNodeWithRetirement(
    in runtime: RetainedViewRuntime, model: FrameAXModel, onRelease: @escaping @MainActor () -> Void
) -> ViewNode {
    let payload = FrameAXRetirement(onRelease)
    return frameAXNode(
        Button("Control") { model.activations += 1 }.frame(width: 120, height: 32)
            .accessibilityIdentifier("subject").accessibilityAction { [payload] in withExtendedLifetime(payload) {} },
        in: runtime)
}

@MainActor
private struct FrameAXNativeList: View {
    let adapter: RetainedLazyListRuntimeAdapter
    let identity: RetainedViewIdentity
    var body: Never { fatalError("The native test primitive has no body") }

    func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            let list = ViewNode(layoutMode: .lazyStack(.vertical(spacing: 0, alignment: .stretch)))
            list.retainedViewIdentity = identity
            list.retainedLazyListAdapter = adapter
            list.retainedSubtreeBuildLease = adapter.installStandaloneBuildLease(in: runtime)
            XCTAssertNotNil(list.retainedSubtreeBuildLease)
            list.layoutFillAxes = .horizontalOnly
            list.accessibilityChildBehavior = .contain
            return list
        }
    }
}
