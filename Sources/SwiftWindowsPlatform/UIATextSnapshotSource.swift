import SwiftWindowsCore

/// Optional internal content retrieval, separate from UIA TextPattern support.
/// A source returns one immutable copy or refuses with nil; an empty document
/// is a non-nil snapshot. No binding, editor, selection, or geometry interface
/// is implied, and the returned value carries no continuing provider authority.
@MainActor
package protocol UIATextSnapshotSource: UIAElementTreeSource {
    func uiaTextSnapshot(elementID: UInt64) -> TextRangeSnapshot?
}
