import SwiftWindowsUI

/// Opted-in targets can reject a stale or temporarily blocked replay before
/// the manager consumes it. Ordinary application targets keep their behavior.
@MainActor
protocol UndoManagerReplayTarget: AnyObject {
    func prepareForUndoReplay() -> Bool
}

struct TextInputUndoSelection {
    var caret: Int
    var selection: RetainedTextSelection?
    var affinity: RetainedTextSelectionAffinity

    init(caret: Int, selection: RetainedTextSelection? = nil, affinity: RetainedTextSelectionAffinity = .automatic) {
        self.caret = caret
        self.selection = selection
        self.affinity = affinity
    }

    @MainActor
    init(node: ViewNode, text: String) {
        caret = min(max(0, node.textInputCaretOffset), text.count)
        selection = node.textInputSelection
        affinity = node.textSelectionAffinity
    }

    func boundValue(in text: String) -> TextSelection? {
        guard let selection else { return nil }
        func index(_ offset: Int) -> String.Index {
            text.index(text.startIndex, offsetBy: min(max(0, offset), text.count))
        }
        let indices: TextSelection.Indices
        switch selection.indices {
        case .insertionPoint(let offset):
            indices = .selection(index(offset)..<index(offset))
        case .range(let range):
            indices = .selection(index(range.lowerBound)..<index(range.upperBound))
        case .ranges(let ranges):
            indices = .multiSelection(RangeSet(ranges.map { index($0.lowerBound)..<index($0.upperBound) }))
        }
        let affinity: TextSelectionAffinity
        switch selection.affinity {
        case .automatic: affinity = .automatic
        case .upstream: affinity = .upstream
        case .downstream: affinity = .downstream
        }
        return TextSelection(indices: indices, affinity: affinity)
    }
}

@MainActor
protocol TextInputUndoClient: AnyObject {
    var undoText: String? { get }
    var undoSelection: TextInputUndoSelection? { get }
    var permitsUndoReplay: Bool { get }
    var undoRuntime: RetainedViewRuntime? { get }
    func refreshUndoConfiguration()
    func applyUndoText(_ text: String, selection: TextInputUndoSelection)
    func invalidateUndoDisplay()
}

/// A session belongs to the retained editor identity, not to one build's
/// Binding closures. It retains one current-text checkpoint and edit deltas.
/// Callers switching equal-content documents must also change the view's id.
@MainActor
final class TextInputUndoSession: UndoManagerReplayTarget {
    struct Edit {
        var offset: Int
        var removed: String
        var inserted: String
        var beforeSelection: TextInputUndoSelection
        var afterSelection: TextInputUndoSelection

        init(
            before: String, after: String, beforeSelection: TextInputUndoSelection,
            afterSelection: TextInputUndoSelection
        ) {
            let old = Array(before)
            let new = Array(after)
            var prefix = 0
            while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
            var suffix = 0
            while suffix < min(old.count, new.count) - prefix,
                old[old.count - 1 - suffix] == new[new.count - 1 - suffix]
            { suffix += 1 }
            offset = prefix
            removed = String(old[prefix..<(old.count - suffix)])
            inserted = String(new[prefix..<(new.count - suffix)])
            self.beforeSelection = beforeSelection
            self.afterSelection = afterSelection
        }
    }

    struct Mutation {
        let generation: UInt64
        let before: String
        let expected: String
        let selection: TextInputUndoSelection
    }

    private(set) weak var manager: UndoManager?
    private weak var client: (any TextInputUndoClient)?
    private var checkpoint: String
    private var pending: Mutation?
    private(set) var generation: UInt64 = 0
    private(set) var isValid = true

    init(manager: UndoManager, text: String) {
        self.manager = manager
        checkpoint = text
    }

    func adopt(_ client: any TextInputUndoClient, text: String) {
        self.client = client
        guard isValid else { return }
        if pending?.expected != text, checkpoint != text {
            reset(to: text)
        }
    }

    func markInvalid() {
        isValid = false
        generation &+= 1
        pending = nil
        checkpoint = ""
    }

    func purgeHistory() {
        manager?.removeAllActions(withTarget: self)
    }

    func invalidate() {
        markInvalid()
        purgeHistory()
    }

    private func reset(to text: String) {
        generation &+= 1
        pending = nil
        checkpoint = text
        purgeHistory()
    }

    func beginEdit(before: String, expected: String, selection: TextInputUndoSelection) -> Mutation? {
        guard isValid else { return nil }
        if pending != nil || checkpoint != before {
            let resetGeneration = generation &+ 1
            reset(to: before)
            // Releasing discarded history can run application deinitializers.
            // A removal or nested edit must not receive a fresh outer ticket.
            guard isValid, generation == resetGeneration else { return nil }
        }
        guard let manager, manager.isUndoRegistrationEnabled, !manager.isUndoing, !manager.isRedoing,
            before != expected
        else { return nil }
        generation &+= 1
        let mutation = Mutation(generation: generation, before: before, expected: expected, selection: selection)
        pending = mutation
        return mutation
    }

    func isCurrent(_ mutation: Mutation) -> Bool {
        isValid && generation == mutation.generation && pending?.generation == mutation.generation
    }

    func cancelEdit(_ mutation: Mutation?) {
        guard let mutation, isCurrent(mutation) else { return }
        generation &+= 1
        pending = nil
    }

    func canWriteReplacement(over text: String, generation expectedGeneration: UInt64) -> Bool {
        isValid && generation == expectedGeneration && pending?.generation == expectedGeneration
            && pending?.before == text
    }

    func finishEdit(_ mutation: Mutation?, text: String, selection: TextInputUndoSelection) {
        guard isValid else { return }
        guard let mutation, isCurrent(mutation) else {
            if checkpoint != text { reset(to: text) }
            return
        }
        guard text == mutation.expected else {
            reset(to: text)
            return
        }
        pending = nil
        checkpoint = text
        let edit = Edit(
            before: mutation.before, after: text, beforeSelection: mutation.selection, afterSelection: selection)
        register(edit, undoing: true)
    }

    func prepareForUndoReplay() -> Bool {
        guard isValid, pending == nil else { return false }
        client?.refreshUndoConfiguration()
        guard isValid, pending == nil, let client, let text = client.undoText else { return false }
        guard checkpoint == text else {
            reset(to: text)
            return false
        }
        return client.permitsUndoReplay
    }

    func belongs(to runtime: RetainedViewRuntime) -> Bool {
        client?.undoRuntime === runtime
    }

    private func register(_ edit: Edit, undoing: Bool) {
        guard isValid, let manager else { return }
        let registrationGeneration = generation
        let isReplay = manager.isUndoing || manager.isRedoing
        let registered = manager.registerUndo(withTarget: self, actionName: "Edit Text") { target in
            target.replay(edit, undoing: undoing)
        }
        // Pruning or invalidating redo can release arbitrary captured
        // payloads, including callbacks that remove or replace this editor.
        if !isValid || generation != registrationGeneration {
            manager.removeAllActions(withTarget: self)
        } else if !registered, !isReplay {
            reset(to: checkpoint)
        }
    }

    private func replay(_ edit: Edit, undoing: Bool) {
        guard isValid, pending == nil, let client, let text = client.undoText,
            text == checkpoint, let selection = client.undoSelection
        else { return }
        let removed = undoing ? edit.inserted : edit.removed
        let inserted = undoing ? edit.removed : edit.inserted
        let characters = Array(text)
        let end = edit.offset + removed.count
        guard edit.offset >= 0, end <= characters.count,
            String(characters[edit.offset..<end]) == removed
        else {
            reset(to: text)
            return
        }
        let expected = String(characters[..<edit.offset]) + inserted + String(characters[end...])
        generation &+= 1
        let mutation = Mutation(generation: generation, before: text, expected: expected, selection: selection)
        pending = mutation
        client.applyUndoText(expected, selection: undoing ? edit.beforeSelection : edit.afterSelection)
        guard isCurrent(mutation), let current = self.client, let actual = current.undoText else { return }
        guard actual == expected else {
            reset(to: actual)
            current.invalidateUndoDisplay()
            return
        }
        pending = nil
        checkpoint = actual
        register(edit, undoing: !undoing)
        self.client?.invalidateUndoDisplay()
    }
}
