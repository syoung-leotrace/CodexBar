import Foundation
import SQLite3
import Testing
@testable import CodexBar

struct CodexAttentionTests {
    @Test(arguments: ["waitingOnApproval", "waitingOnUserInput"])
    func `explicit waiting flags require attention`(flag: String) throws {
        var state = CodexAttentionState()
        try state.apply(self.snapshot(id: "one", flags: [flag]))
        #expect(state.needsAttention)
        try state.apply(self.snapshot(id: "one", flags: []))
        #expect(!state.needsAttention)
    }

    @Test
    func `one answered task does not clear another waiting task`() throws {
        var state = CodexAttentionState()
        try state.apply(self.snapshot(id: "one", flags: ["waitingOnApproval"]))
        try state.apply(self.snapshot(id: "two", flags: ["waitingOnUserInput"]))
        try state.apply(self.snapshot(id: "one", flags: []))
        #expect(state.needsAttention)
        state.apply(CodexAttentionEvent(kind: .closed("two")))
        #expect(!state.needsAttention)
    }

    @Test
    func `idle and unknown flags never mean input is needed`() throws {
        var state = CodexAttentionState()
        try state.apply(self.snapshot(id: "one", flags: ["waitingOnApproval"], type: "idle"))
        try state.apply(self.snapshot(id: "two", flags: ["unknownFlag"]))
        #expect(!state.needsAttention)
    }

    @Test
    func `owner disconnect and monitor reset remove stale attention`() throws {
        var state = CodexAttentionState()
        try state.apply(self.snapshot(id: "one", flags: ["waitingOnApproval"]))
        state.apply(CodexAttentionEvent(kind: .ownerDisconnected("owner")))
        #expect(!state.needsAttention)
        try state.apply(self.snapshot(id: "one", flags: ["waitingOnApproval"]))
        state.reset()
        #expect(!state.needsAttention)
    }

    @Test
    func `remote snapshots and unsupported versions are ignored`() throws {
        var state = CodexAttentionState()
        try state.apply(self.snapshot(id: "one", flags: ["waitingOnApproval"], host: "remote"))
        try state.apply(self.snapshot(id: "one", flags: ["waitingOnApproval"], version: 99))
        state.apply(CodexAttentionEvent.decode(Data("invalid".utf8)))
        #expect(!state.needsAttention)
    }

    @Test
    func `nested status patches request a fresh snapshot`() throws {
        let event = try CodexAttentionEvent.decode(JSONSerialization.data(withJSONObject: [
            "type": "broadcast", "method": "thread-stream-state-changed", "version": 11,
            "params": ["hostId": "local", "conversationId": "one", "change": [
                "type": "patches", "patches": [[
                    "op": "replace", "path": ["threadRuntimeStatus", "activeFlags", 0],
                    "value": "waitingOnUserInput",
                ]],
            ]],
        ]))
        guard case .refresh("one") = event.kind else {
            Issue.record("Expected a fresh status snapshot")
            return
        }
    }

    @Test
    func `thread discovery reads unarchived IDs from a synthetic home`() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        var database: OpaquePointer?
        #expect(sqlite3_open(home.appendingPathComponent("state_5.sqlite").path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        let sql = "CREATE TABLE threads (id TEXT, archived INTEGER, updated_at INTEGER); "
            + "INSERT INTO threads VALUES ('active', 0, 123), ('archived', 1, 456);"
        #expect(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
        #expect(CodexAttentionMonitor.threadUpdates(home: home) == ["active": 123])
    }

    @Test
    func `runtime replacement patches update without another snapshot`() throws {
        let event = try CodexAttentionEvent.decode(JSONSerialization.data(withJSONObject: [
            "type": "broadcast", "method": "thread-stream-state-changed", "version": 11,
            "sourceClientId": "owner",
            "params": ["hostId": "local", "conversationId": "one", "change": [
                "type": "patches", "patches": [[
                    "op": "replace", "path": ["threadRuntimeStatus"],
                    "value": ["type": "active", "activeFlags": ["waitingOnUserInput"]],
                ]],
            ]],
        ]))
        var state = CodexAttentionState()
        state.apply(event)
        #expect(state.needsAttention)
    }

    @Test
    func `large transcript fields are discarded without interpreting their contents`() throws {
        let input = try JSONSerialization.data(withJSONObject: [
            "turnHistory": ["content": String(repeating: "ignored transcript", count: 100_000)],
            "turns": [["threadRuntimeStatus": ["type": "active", "activeFlags": ["waitingOnApproval"]]]],
            "threadRuntimeStatus": ["type": "idle"],
            "description": "a string containing \"turns\": and braces {}[]",
        ])
        let metadata = CodexAttentionJSON.metadata(input)
        #expect(metadata.count < 250)
        let object = try #require(JSONSerialization.jsonObject(with: metadata) as? [String: Any])
        #expect(object["turns"] is NSNull)
        #expect((object["threadRuntimeStatus"] as? [String: String])?["type"] == "idle")
    }

    @Test(arguments: ["", "\"", "{\"turns\":", "{\"unclosed", "[\"\\"])
    func `truncated JSON is ignored safely`(input: String) {
        let event = CodexAttentionEvent.decode(Data(input.utf8))
        guard case .ignored = event.kind else {
            Issue.record("Expected invalid data to be ignored")
            return
        }
    }

    private func snapshot(
        id: String,
        flags: [String],
        type: String = "active",
        host: String = "local",
        version: Int = 11) throws -> CodexAttentionEvent
    {
        try CodexAttentionEvent.decode(JSONSerialization.data(withJSONObject: [
            "type": "broadcast", "method": "thread-stream-state-changed", "version": version,
            "sourceClientId": "owner", "params": [
                "hostId": host, "conversationId": id,
                "change": ["type": "snapshot", "conversationState": [
                    "threadRuntimeStatus": ["type": type, "activeFlags": flags],
                ]],
            ],
        ]))
    }
}
