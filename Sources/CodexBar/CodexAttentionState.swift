import Foundation

struct CodexAttentionEvent: Sendable {
    enum Kind: Sendable {
        case initialized(String)
        case status(String, String, Bool)
        case refresh(String)
        case closed(String)
        case inactive(String)
        case ownerDisconnected(String)
        case discovery(String)
        case incompatible
        case ignored
    }

    let kind: Kind

    static func decode(_ data: Data) -> Self {
        guard let message = try? JSONSerialization
            .jsonObject(with: CodexAttentionJSON.metadata(data)) as? [String: Any]
        else {
            return Self(kind: .ignored)
        }
        if message["type"] as? String == "client-discovery-request",
           let id = message["requestId"] as? String
        {
            return Self(kind: .discovery(id))
        }
        if message["method"] as? String == "initialize",
           message["resultType"] as? String == "success",
           let result = message["result"] as? [String: Any], let id = result["clientId"] as? String
        {
            return Self(kind: .initialized(id))
        }
        guard message["type"] as? String == "broadcast",
              let method = message["method"] as? String,
              let params = message["params"] as? [String: Any]
        else { return Self(kind: .ignored) }
        if method == "client-status-changed", params["status"] as? String == "disconnected",
           let owner = params["clientId"] as? String
        {
            return Self(kind: .ownerDisconnected(owner))
        }
        guard params["hostId"] as? String == "local",
              let id = params["conversationId"] as? String
        else { return Self(kind: .ignored) }
        if method == "thread-archived" { return Self(kind: .closed(id)) }
        if method == "thread-stream-following-status-requested" {
            return Self(kind: .refresh(id))
        }
        guard method == "thread-stream-state-changed" else { return Self(kind: .ignored) }
        guard message["version"] as? Int == 11 else { return Self(kind: .incompatible) }
        guard let change = params["change"] as? [String: Any]
        else { return Self(kind: .ignored) }
        if change["type"] as? String == "snapshot",
           let state = change["conversationState"] as? [String: Any],
           let owner = message["sourceClientId"] as? String
        {
            let status = state["threadRuntimeStatus"] as? [String: Any]
            guard status?["type"] as? String == "active" else { return Self(kind: .inactive(id)) }
            let flags = status?["activeFlags"] as? [String] ?? []
            let waiting = status?["type"] as? String == "active"
                && flags.contains { $0 == "waitingOnApproval" || $0 == "waitingOnUserInput" }
            return Self(kind: .status(id, owner, waiting))
        }
        if change["type"] as? String == "patches",
           let patches = change["patches"] as? [[String: Any]],
           let patch = patches.last(where: { ($0["path"] as? [Any])?.first as? String == "threadRuntimeStatus" })
        {
            if (patch["path"] as? [String]) == ["threadRuntimeStatus"],
               let status = patch["value"] as? [String: Any],
               let owner = message["sourceClientId"] as? String
            {
                guard status["type"] as? String == "active" else { return Self(kind: .inactive(id)) }
                let flags = status["activeFlags"] as? [String] ?? []
                let waiting = status["type"] as? String == "active"
                    && flags.contains { $0 == "waitingOnApproval" || $0 == "waitingOnUserInput" }
                return Self(kind: .status(id, owner, waiting))
            }
            return Self(kind: .refresh(id))
        }
        return Self(kind: .ignored)
    }
}

struct CodexAttentionState {
    private var waitingOwners: [String: String] = [:]

    var needsAttention: Bool {
        !self.waitingOwners.isEmpty
    }

    mutating func apply(_ event: CodexAttentionEvent) {
        switch event.kind {
        case let .status(id, owner, waiting):
            self.waitingOwners[id] = waiting ? owner : nil
        case let .closed(id), let .inactive(id):
            self.waitingOwners[id] = nil
        case .incompatible:
            self.reset()
        case let .ownerDisconnected(owner):
            self.waitingOwners = self.waitingOwners.filter { $0.value != owner }
        default:
            break
        }
    }

    mutating func reset() {
        self.waitingOwners.removeAll()
    }
}
