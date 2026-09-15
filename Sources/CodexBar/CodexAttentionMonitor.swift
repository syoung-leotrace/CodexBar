import Foundation
import Network
import SQLite3

@MainActor
final class CodexAttentionMonitor {
    var onChange: (() -> Void)?
    private(set) var state = CodexAttentionState()
    private var connection: NWConnection?
    private var clientID: String?
    private var enabled = false
    private var compatible = true
    private var generation = 0
    private var knownThreads: [String: Int64] = [:]
    private var followedThreads: Set<String> = []
    private var refreshTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private let home: URL

    var needsAttention: Bool {
        self.state.needsAttention
    }

    var isConnected: Bool {
        self.clientID != nil && self.compatible
    }

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) {
        self.home = home
    }

    func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        if enabled {
            self.connect()
        } else {
            self.disconnect()
        }
    }

    private func connect() {
        guard self.enabled, self.connection == nil else { return }
        let socket = self.home.appendingPathComponent("ipc/ipc.sock")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: socket.path),
              attributes[.type] as? FileAttributeType == .typeSocket,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid()
        else {
            self.scheduleRetry()
            return
        }
        self.generation += 1
        let generation = self.generation
        let connection = NWConnection(to: .unix(path: socket.path), using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                switch status {
                case .ready:
                    self.send([
                        "type": "request", "method": "initialize", "requestId": UUID().uuidString,
                        "params": ["clientType": "codexbar"],
                    ])
                    self.receiveHeader(generation: generation)
                case .failed, .cancelled, .waiting:
                    self.disconnect()
                    self.scheduleRetry()
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
    }

    private func disconnect() {
        self.generation += 1
        self.refreshTask?.cancel()
        self.refreshTask = nil
        self.retryTask?.cancel()
        self.retryTask = nil
        self.receiveTask?.cancel()
        self.receiveTask = nil
        self.connection?.cancel()
        self.connection = nil
        self.clientID = nil
        self.compatible = true
        self.knownThreads.removeAll()
        self.followedThreads.removeAll()
        self.state.reset()
        self.onChange?()
    }

    private func scheduleRetry() {
        guard self.enabled, self.retryTask == nil else { return }
        self.retryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard let self else { return }
            self.retryTask = nil
            self.connect()
        }
    }

    private func receiveHeader(generation: Int) {
        self.receive(count: 4, generation: generation) { [weak self] data in
            let length = data.enumerated().reduce(0) { $0 | (Int($1.element) << ($1.offset * 8)) }
            guard length > 0, length <= 256 * 1024 * 1024 else {
                self?.disconnect()
                self?.scheduleRetry()
                return
            }
            self?.receive(count: length, generation: generation) { [weak self] payload in
                self?.receiveTask = Task { [weak self] in
                    let event = await Task.detached(priority: .utility) {
                        CodexAttentionEvent.decode(payload)
                    }.value
                    guard let self, self.generation == generation, !Task.isCancelled else { return }
                    self.handle(event)
                    self.receiveHeader(generation: generation)
                }
            }
        }
    }

    private func receive(
        count: Int,
        generation: Int,
        completion: @escaping @MainActor (Data) -> Void)
    {
        self.connection?
            .receive(minimumIncompleteLength: count, maximumLength: count) { [weak self] data, _, _, error in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == generation else { return }
                    guard error == nil, let data, data.count == count else {
                        self.disconnect()
                        self.scheduleRetry()
                        return
                    }
                    completion(data)
                }
            }
    }

    private func handle(_ event: CodexAttentionEvent) {
        let previous = self.needsAttention
        let wasConnected = self.isConnected
        if case .incompatible = event.kind { self.compatible = false }
        self.state.apply(event)
        if previous != self.needsAttention || wasConnected != self.isConnected { self.onChange?() }
        switch event.kind {
        case let .initialized(id):
            self.clientID = id
            self.onChange?()
            self.startDiscovery()
        case let .refresh(id):
            self.follow(id)
        case let .closed(id):
            self.follow(id, following: false)
            self.knownThreads[id] = nil
        case let .inactive(id):
            self.follow(id, following: false)
        case let .discovery(id):
            self.send([
                "type": "client-discovery-response", "requestId": id,
                "response": ["canHandle": false],
            ])
        default:
            break
        }
    }

    private func startDiscovery() {
        self.refreshTask?.cancel()
        let home = self.home
        let generation = self.generation
        self.refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                let threads = await Task.detached(priority: .utility) { Self.threadUpdates(home: home) }.value
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                if let threads {
                    for (id, updatedAt) in threads where self.knownThreads[id] != updatedAt {
                        if !self.followedThreads.contains(id) { self.follow(id) }
                    }
                    for id in Set(self.knownThreads.keys).subtracting(threads.keys) {
                        self.handle(CodexAttentionEvent(kind: .closed(id)))
                    }
                    self.knownThreads = threads
                }
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }

    private func follow(_ id: String, following: Bool = true) {
        guard let clientID else { return }
        if following {
            self.followedThreads.insert(id)
        } else {
            self.followedThreads.remove(id)
        }
        self.send([
            "type": "broadcast", "method": "thread-stream-following-changed", "version": 1,
            "sourceClientId": clientID,
            "params": ["conversationId": id, "hostId": "local", "following": following],
        ])
    }

    private func send(_ message: [String: Any]) {
        guard let payload = try? JSONSerialization.data(withJSONObject: message) else { return }
        var length = UInt32(payload.count).littleEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(payload)
        self.connection?.send(content: frame, completion: .contentProcessed { _ in })
    }

    nonisolated static func threadUpdates(home: URL) -> [String: Int64]? {
        var database: OpaquePointer?
        let path = home.appendingPathComponent("state_5.sqlite").path
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            return nil
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 100)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT id, updated_at FROM threads WHERE archived = 0", -1, &statement, nil)
            == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        var ids: [String: Int64] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) { ids[String(cString: text)] = sqlite3_column_int64(
                statement,
                1) }
        }
        return ids
    }
}
