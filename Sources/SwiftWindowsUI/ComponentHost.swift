@MainActor
public final class ComponentHost {
    public let runtime: RetainedViewRuntime

    private var buildComponents: (() -> [Component])?

    public init(runtime: RetainedViewRuntime) {
        self.runtime = runtime
    }

    public func setContent(_ component: Component) {
        buildComponents = { [component] }
        reload()
    }

    public func setContent(@ComponentBuilder _ content: @escaping () -> [Component]) {
        buildComponents = content
        reload()
    }

    public func reload() {
        runtime.root.removeAllChildren()

        guard let buildComponents else {
            return
        }

        for component in buildComponents() {
            runtime.root.addChild(component.makeNode(runtime: runtime))
        }
    }
}
