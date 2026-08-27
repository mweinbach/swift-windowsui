import Foundation
import SwiftWindowsUI

/// One invocation owns its resolution cache. A source is measured only when
/// requested; merely declaring a symbol never adds it to the Canvas's input
/// tree or to the surrounding scene.
@MainActor
final class CanvasSymbolResolver {
    private let symbols: @MainActor () -> [AnyView]
    private let context: ViewBuildContext
    private var resolved: [AnyHashable: GraphicsContext.ResolvedSymbol] = [:]
    private var missing: Set<AnyHashable> = []
    private static let maximumLookups = 1_024
    private static let maximumDeclarationNodes = 4_096
    private static let maximumDeclarationDepth = 128
    private var reportedLimit = false

    init(symbols: @escaping @MainActor () -> [AnyView], context: ViewBuildContext) {
        self.symbols = symbols
        self.context = context
    }

    func resolve(_ identifier: AnyHashable) -> GraphicsContext.ResolvedSymbol? {
        if let symbol = resolved[identifier] { return symbol }
        guard !missing.contains(identifier) else { return nil }
        guard resolved.count + missing.count < Self.maximumLookups else {
            reportLimit()
            return nil
        }

        let source = CanvasSymbolSource(displayScale: context.displayScale) { runtime in
            ViewBuildContextScope.withCurrent(context) {
                let declarationRoot = composeComponent(from: symbols(), context: context).makeNode(runtime: runtime)
                return selectedTree(in: declarationRoot, matching: identifier)
            }
        }
        guard let source else {
            missing.insert(identifier)
            return nil
        }
        let symbol = GraphicsContext.ResolvedSymbol(source: source)
        resolved[identifier] = symbol
        return symbol
    }

    /// Retained traits survive Group, custom bodies and repeated AnyView
    /// erasure. Keep the wrappers on the route to the selected declaration
    /// (for example a frame outside `.tag`) and remove unrelated siblings.
    /// Duplicate tags deterministically select the first declaration; exact
    /// native behavior for duplicates and tags inside arbitrary layout
    /// containers has not been qualified.
    private func selectedTree(in root: ViewNode, matching identifier: AnyHashable) -> ViewNode? {
        let valuesKey = retainedContainerValuesIdentifier()
        var preorder: [ViewNode] = []
        var pending: [(ViewNode, Int)] = [(root, 0)]
        var seen: Set<ObjectIdentifier> = []
        while let (node, depth) = pending.popLast() {
            guard depth <= Self.maximumDeclarationDepth,
                preorder.count < Self.maximumDeclarationNodes,
                seen.insert(ObjectIdentifier(node)).inserted
            else {
                reportLimit()
                return nil
            }
            preorder.append(node)
            for child in node.children.reversed() { pending.append((child, depth + 1)) }
        }

        // An explicit tag on the view produced by a ForEach takes precedence
        // over its implicit ID, even if a layout wrapper owns the implicit
        // trait. Keep the Hashable value itself, never its description.
        var containsExplicit: Set<ObjectIdentifier> = []
        for node in preorder.reversed() {
            let values = node.retainedContainerValues[valuesKey] as? ContainerValues
            if values?.hasExplicitSymbolTag == true
                || node.children.contains(where: { containsExplicit.contains(ObjectIdentifier($0)) })
            {
                containsExplicit.insert(ObjectIdentifier(node))
            }
        }
        guard
            let selected = preorder.first(where: { node in
                guard let values = node.retainedContainerValues[valuesKey] as? ContainerValues else { return false }
                if values.containsExplicitSymbolTag(identifier) { return true }
                return !containsExplicit.contains(ObjectIdentifier(node)) && values.implicitSymbolTag == identifier
            })
        else { return nil }

        var child = selected
        while let parent = child.parent {
            for sibling in parent.children where sibling !== child { parent.removeChild(sibling) }
            if parent === root { break }
            child = parent
        }
        return root
    }

    private func reportLimit() {
        guard !reportedLimit else { return }
        reportedLimit = true
        FileHandle.standardError.write(
            Data("[WinSwiftUI] Canvas symbol lookup exceeded its bounded declaration or lookup budget.\n".utf8))
    }
}
