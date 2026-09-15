import Foundation

enum CodexAttentionJSON {
    private static let discardedKeys: Set<String> = [
        "turns", "turnHistory", "latestTokenUsageInfo", "acceptedTextChanges", "requests",
    ]

    static func metadata(_ data: Data) -> Data {
        data.withUnsafeBytes { bytes in
            let input = bytes.bindMemory(to: UInt8.self)
            var output = Data()
            var cursor = 0
            var copiedThrough = 0
            while cursor < input.count {
                guard input[cursor] == 34 else {
                    cursor += 1
                    continue
                }
                let start = cursor
                cursor = self.stringEnd(input, start: cursor)
                let keyEnd = cursor
                while cursor < input.count, self.isWhitespace(input[cursor]) {
                    cursor += 1
                }
                guard cursor < input.count, input[cursor] == 58,
                      keyEnd - start >= 2, keyEnd - start < 32, input[keyEnd - 1] == 34,
                      let key = String(bytes: input[(start + 1)..<(keyEnd - 1)], encoding: .utf8),
                      self.discardedKeys.contains(key)
                else { continue }
                cursor += 1
                while cursor < input.count, self.isWhitespace(input[cursor]) {
                    cursor += 1
                }
                output.append(contentsOf: input[copiedThrough..<cursor])
                output.append(contentsOf: "null".utf8)
                cursor = self.valueEnd(input, start: cursor)
                copiedThrough = cursor
            }
            guard copiedThrough > 0 else { return data }
            output.append(contentsOf: input[copiedThrough..<input.count])
            return output
        }
    }

    private static func valueEnd(_ input: UnsafeBufferPointer<UInt8>, start: Int) -> Int {
        guard start < input.count else { return start }
        if input[start] == 34 { return self.stringEnd(input, start: start) }
        if input[start] != 123, input[start] != 91 {
            var cursor = start
            while cursor < input.count, ![UInt8(44), 125, 93].contains(input[cursor]),
                  !self.isWhitespace(input[cursor])
            {
                cursor += 1
            }
            return cursor
        }
        var depth = 0
        var cursor = start
        while cursor < input.count {
            switch input[cursor] {
            case 34:
                cursor = self.stringEnd(input, start: cursor)
                continue
            case 123, 91:
                depth += 1
            case 125, 93:
                depth -= 1
                if depth == 0 { return cursor + 1 }
            default:
                break
            }
            cursor += 1
        }
        return cursor
    }

    private static func stringEnd(_ input: UnsafeBufferPointer<UInt8>, start: Int) -> Int {
        var cursor = start + 1
        while cursor < input.count {
            if input[cursor] == 92 {
                cursor = min(input.count, cursor + 2)
            } else if input[cursor] == 34 {
                return cursor + 1
            } else {
                cursor += 1
            }
        }
        return cursor
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 32 || byte == 10 || byte == 13 || byte == 9
    }
}
