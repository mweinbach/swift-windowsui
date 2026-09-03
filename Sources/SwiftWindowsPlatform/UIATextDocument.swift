import SwiftWindowsCore

/// Internal held-text capability only. This does not advertise TextPattern.
@MainActor
package protocol UIATextDocumentSource: UIAElementTreeSource {
    func uiaTextDocument(elementID: UInt64) -> UIATextDocument?
}

/// Implementations retain original weak witnesses, never a replacement lookup.
@MainActor
package protocol UIATextDocumentAuthority: AnyObject {
    func isCurrent() -> Bool
    func matchesOriginalDocument(_ other: any UIATextDocumentAuthority) -> Bool
}

extension UIATextDocumentAuthority {
    package func matchesOriginalDocument(_ other: any UIATextDocumentAuthority) -> Bool {
        self === other
    }
}

/// Internal peer operations distinguish a stale origin from a different one.
/// Values are equality (0/1) or endpoint ordering (-1/0/1), never text units.
package enum UIATextRangePeerResult: Equatable, Sendable {
    case unavailable
    case incompatible
    case value(Int32)
}

/// An immutable text copy with independently revocable original authority.
/// Every operation revalidates authority. An observed refusal is permanent.
/// These actor-isolated objects may travel as opaque internal request values;
/// no native pointer, callback, selection, geometry, or COM interface is implied.
@MainActor
package final class UIATextDocument: Equatable {
    private let snapshot: TextRangeSnapshot
    private let authority: any UIATextDocumentAuthority
    private var isInvalidated = false
    private var hasProviderOwner = false
    private weak var providerOwner: UIAProviderBridge?

    package init(snapshot: TextRangeSnapshot, authority: any UIATextDocumentAuthority) {
        self.snapshot = snapshot
        self.authority = authority
    }

    package nonisolated static func == (lhs: UIATextDocument, rhs: UIATextDocument) -> Bool {
        lhs === rhs
    }

    package var isCurrent: Bool {
        guard !isInvalidated else { return false }
        guard ownerIsCurrent, authority.isCurrent(), ownerIsCurrent, !isInvalidated else {
            isInvalidated = true
            return false
        }
        return true
    }

    private var ownerIsCurrent: Bool {
        !hasProviderOwner || providerOwner?.permitsHeldTextReads == true
    }

    /// Binding is one-way. Another provider cannot adopt an existing document.
    package func bind(to owner: UIAProviderBridge) -> Bool {
        guard !hasProviderOwner else { return providerOwner === owner && isCurrent }
        hasProviderOwner = true
        providerOwner = owner
        return isCurrent
    }

    fileprivate func isOwned(by owner: UIAProviderBridge) -> Bool {
        hasProviderOwner && providerOwner === owner
    }

    /// Callback-free terminal observation only, never fresh read authority.
    fileprivate var hasObservedInvalidation: Bool { isInvalidated }

    /// nil means stale; false means two current but different original owners.
    /// Object equality remains unchanged: compatibility is an explicit operation.
    fileprivate func isCompatible(with other: UIATextDocument) -> Bool? {
        guard isCurrent, other.isCurrent, isCurrent, !isInvalidated, !other.isInvalidated else { return nil }
        let compatible =
            hasSameProviderOwner(as: other)
            && snapshot.text.utf16.elementsEqual(other.snapshot.text.utf16)
            && authority.matchesOriginalDocument(other.authority)
            && other.authority.matchesOriginalDocument(authority)
        guard isCurrent, other.isCurrent, isCurrent, !isInvalidated, !other.isInvalidated else { return nil }
        return compatible
    }

    @inline(never)
    private func hasSameProviderOwner(as other: UIATextDocument) -> Bool {
        hasProviderOwner == other.hasProviderOwner && providerOwner === other.providerOwner
    }

    package func documentRange() -> UIATextRange? {
        guard isCurrent else { return nil }
        return UIATextRange(document: self, span: snapshot.documentRange)
    }

    package func range(utf16Start: Int, utf16End: Int) -> UIATextRange? {
        guard isCurrent, let span = snapshot.range(utf16Start: utf16Start, utf16End: utf16End) else {
            return nil
        }
        return UIATextRange(document: self, span: span)
    }

    fileprivate func text(in span: TextRangeSpan, maximumUTF16Length: Int) throws -> String? {
        guard isCurrent else { return nil }
        let result = try snapshot.getText(in: span, maximumUTF16Length: maximumUTF16Length)
        return isCurrent ? result : nil
    }
}

/// A held range never accepts a caller-supplied document ID or text snapshot.
/// Its span is immutable; clones share the same original document authority.
@MainActor
package final class UIATextRange: Equatable {
    private let document: UIATextDocument
    private let span: TextRangeSpan

    fileprivate init(document: UIATextDocument, span: TextRangeSpan) {
        self.document = document
        self.span = span
    }

    package nonisolated static func == (lhs: UIATextRange, rhs: UIATextRange) -> Bool {
        lhs === rhs
    }

    package var isCurrent: Bool { document.isCurrent }

    package func isOwned(by owner: UIAProviderBridge) -> Bool { document.isOwned(by: owner) }

    package func clone() -> UIATextRange? {
        guard isCurrent else { return nil }
        return UIATextRange(document: document, span: span)
    }

    package func compareEndpoints(
        _ endpoint: TextRangeEndpoint, to other: UIATextRange, endpoint otherEndpoint: TextRangeEndpoint
    ) -> Int? {
        guard document === other.document, isCurrent else { return nil }
        return span.compareEndpoint(endpoint, to: other.span, endpoint: otherEndpoint)
    }

    package func compareOriginalRange(to other: UIATextRange) -> UIATextRangePeerResult {
        guard let compatible = document.isCompatible(with: other.document) else { return .unavailable }
        guard compatible else { return .incompatible }
        return .value(span == other.span ? 1 : 0)
    }

    /// Only denies a result after paired authority callbacks. It does not
    /// replace either range's currentness or the native call/session checks.
    package func hasNoObservedInvalidation(with other: UIATextRange) -> Bool {
        !document.hasObservedInvalidation && !other.document.hasObservedInvalidation
    }

    package func compareOriginalEndpoint(
        _ endpoint: TextRangeEndpoint, to other: UIATextRange, endpoint otherEndpoint: TextRangeEndpoint
    ) -> UIATextRangePeerResult {
        guard let compatible = document.isCompatible(with: other.document) else { return .unavailable }
        guard compatible,
            let distance = span.compareEndpoint(endpoint, to: other.span, endpoint: otherEndpoint)
        else { return .incompatible }
        return .value(distance < 0 ? -1 : distance > 0 ? 1 : 0)
    }

    /// Uses the value helper's explicit local policy: -1 is unlimited,
    /// nonnegative limits count UTF16 units without splitting a Character,
    /// and other negatives throw. This is not native UIA truncation parity.
    package func getText(maximumUTF16Length: Int = -1) throws -> String? {
        try document.text(in: span, maximumUTF16Length: maximumUTF16Length)
    }
}
