/// A deferred native wake is held while any owned window dispatch, close
/// attempt, or native modal call can still reenter the same UI thread.
@MainActor
protocol Win32DispatchWakeClient: AnyObject {
    /// Rearms at most one owned wake without executing mailbox work or releasing
    /// application payloads inline. Any failure notification/retirement is
    /// returned for delivery after the rearm pass has cleared its own guard.
    func dispatchScopeDidBecomeIdle() -> (@MainActor () -> Void)?
}

@MainActor
enum Win32DispatchScope {
    private final class WeakClient {
        weak var value: (any Win32DispatchWakeClient)?

        init(_ value: any Win32DispatchWakeClient) { self.value = value }
    }

    private static var windowDepth = 0
    private static var modalDepth = 0
    private static var closeDepth = 0
    private static var mailboxDepth = 0
    private static var deliveryDepth = 0
    private static var isRearming = false
    private static var clients: [ObjectIdentifier: WeakClient] = [:]
    private static var registrationsDuringRearm: [AnyObject] = []

    /// A top-level mailbox wndproc counts as one window dispatch. Requiring
    /// zero here would defer every legitimate native wake forever.
    static var canDeliverWindowWake: Bool {
        windowDepth == 1 && modalDepth == 0 && closeDepth == 0 && mailboxDepth == 0 && !isRearming
    }

    /// A tagged attempt can run directly or in the one owned mailbox delivery,
    /// but never from a nested native/modal/cleanup pump. Ordinary WM_CLOSE
    /// keeps its existing public delegate semantics.
    static func permitsTaggedClose(isOwnedRetry: Bool) -> Bool {
        let isOutsideDispatch = windowDepth == 0 && mailboxDepth == 0
        let isOwnedDelivery = windowDepth == 1 && mailboxDepth == 1 && deliveryDepth == 1
        return modalDepth == 0 && closeDepth == 0
            && (isOutsideDispatch || (isOwnedDelivery && isOwnedRetry)) && !isRearming
    }

    private static var canRearm: Bool {
        windowDepth == 0 && modalDepth == 0 && closeDepth == 0 && mailboxDepth == 0 && !isRearming
    }

    static func withWindowDispatch<Result>(_ body: () throws -> Result) rethrows -> Result {
        windowDepth += 1
        defer {
            windowDepth -= 1
            rearmIfIdle()
        }
        return try body()
    }

    /// Wrap the actual owned common-dialog invocation, including calls entered
    /// from outside a wndproc. This does not control third-party modal pumps.
    static func withNativeModal<Result>(_ body: () throws -> Result) rethrows -> Result {
        modalDepth += 1
        defer {
            modalDepth -= 1
            rearmIfIdle()
        }
        return try body()
    }

    static func beginCloseAttempt() { closeDepth += 1 }

    static func endCloseAttempt() {
        precondition(closeDepth > 0)
        closeDepth -= 1
        rearmIfIdle()
    }

    static func withMailboxWork<Result>(_ body: () throws -> Result) rethrows -> Result {
        mailboxDepth += 1
        defer {
            mailboxDepth -= 1
            rearmIfIdle()
        }
        return try body()
    }

    /// Only the detached live record's action gets tagged-close permission.
    /// Failure observers and ARC cleanup use withMailboxWork instead, even
    /// though both scopes prevent another mailbox delivery from reentering.
    static func withMailboxDelivery<Result>(_ body: () throws -> Result) rethrows -> Result {
        precondition(mailboxDepth > 0)
        deliveryDepth += 1
        defer { deliveryDepth -= 1 }
        return try body()
    }

    static func requestWakeWhenIdle(_ client: any Win32DispatchWakeClient) {
        // Weak queue ownership must not release a newly registered client in
        // the middle of the posting pass. These pins end in its cleanup scope.
        if isRearming { registrationsDuringRearm.append(client) }
        clients[ObjectIdentifier(client)] = WeakClient(client)
        rearmIfIdle()
    }

    private static func rearmIfIdle() {
        guard canRearm, !clients.isEmpty else { return }
        isRearming = true
        var visited: Set<ObjectIdentifier> = []
        var pinnedClients: [AnyObject] = []
        var completions: [@MainActor () -> Void] = []
        // A posting callback may register a different client. Process each live
        // client at most once; a self-registration coalesces instead of spinning.
        while !clients.isEmpty {
            let pending = clients
            clients.removeAll(keepingCapacity: true)
            for entry in pending.values {
                guard let client = entry.value else { continue }
                let identifier = ObjectIdentifier(client)
                guard visited.insert(identifier).inserted else { continue }
                pinnedClients.append(client)
                if let completion = client.dispatchScopeDidBecomeIdle() {
                    completions.append(completion)
                }
            }
        }
        var registrationPins = registrationsDuringRearm
        registrationsDuringRearm = []
        isRearming = false
        // Failure observers/ARC cleanup can pump a modal loop. Their nested
        // wakes defer to this mailbox scope, whose exit can now rearm normally.
        // No failed posting is retried automatically.
        withMailboxWork {
            while !completions.isEmpty {
                var completion: (@MainActor () -> Void)? = completions.removeFirst()
                completion?()
                completion = nil
            }
            pinnedClients.removeAll()
            registrationPins.removeAll()
        }
    }
}
