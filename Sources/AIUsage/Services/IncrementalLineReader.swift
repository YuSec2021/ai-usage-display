import Foundation

enum IncrementalLineReader {
    struct Cursor {
        var offset: UInt64 = 0
        var remainder = Data()
    }

    /// Consume only the observed file size; later appends belong to the next
    /// refresh. All I/O completes before consumers mutate their business state.
    static func read(
        from url: URL,
        size: UInt64,
        cursor: Cursor,
        initialOffset: (FileHandle) throws -> UInt64 = { _ in 0 },
        consume: (Data) -> Bool
    ) throws -> Cursor {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let initialRead = cursor.offset == 0
        let start = initialRead ? try initialOffset(handle) : cursor.offset
        guard start <= size, size - start <= UInt64(Int.max) else { throw CocoaError(.fileReadCorruptFile) }
        try handle.seek(toOffset: start)
        var incoming = try handle.read(upToCount: Int(size - start)) ?? Data()
        guard incoming.count == Int(size - start) else { throw CocoaError(.fileReadCorruptFile) }
        if initialRead, start > 0, let newline = incoming.firstIndex(of: 0x0A) {
            incoming.removeSubrange(incoming.startIndex...newline)
        }

        var combined = cursor.remainder
        combined.append(incoming)
        var lines = combined.split(separator: 0x0A, omittingEmptySubsequences: false)
        let finalLine = combined.last == 0x0A ? nil : lines.popLast().map { Data($0) }
        for line in lines where !line.isEmpty { _ = consume(Data(line)) }
        var remainder = Data()
        if let finalLine, !finalLine.isEmpty, !consume(finalLine) { remainder = finalLine }
        return Cursor(offset: size, remainder: remainder)
    }
}
