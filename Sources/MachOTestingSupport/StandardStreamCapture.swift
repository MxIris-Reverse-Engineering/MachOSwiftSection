import Foundation

/// Captures what a body writes to a real standard stream file descriptor.
///
/// The redirect is done at the **file-descriptor** level (`dup2`), not by
/// swapping a `FileHandle`, because that is the only thing that also catches
/// writes performed by `FileHandle.standardError` / `print` inside library code
/// under test — which is the whole point: several degradation paths in this
/// package are only observable as a stderr diagnostic (a renderer whose printers
/// carry no event handlers has nowhere else to report to), and the rule that
/// nothing may reach stdout is likewise a property of the real descriptor.
///
/// Serialize any suite using this — a process has one set of descriptors.
package enum StandardStreamCapture {
    /// Redirects `STDERR_FILENO` for the duration of `body` and returns what was
    /// written to it.
    ///
    /// The `isolated` parameter (SE-0420) makes this inherit the caller's
    /// isolation, so `body` never crosses an isolation domain — without it, a
    /// closure capturing the test's own local state is a `sending` violation at
    /// every call site.
    package static func standardError(
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> Void
    ) async throws -> String {
        try await capture(fileDescriptor: STDERR_FILENO, flushing: stderr, body)
    }

    /// Redirects `STDOUT_FILENO` for the duration of `body` and returns what was
    /// written to it.
    package static func standardOutput(
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> Void
    ) async throws -> String {
        try await capture(fileDescriptor: STDOUT_FILENO, flushing: stdout, body)
    }

    private static func capture(
        isolation: isolated (any Actor)? = #isolation,
        fileDescriptor: Int32,
        flushing stream: UnsafeMutablePointer<FILE>,
        _ body: () async throws -> Void
    ) async throws -> String {
        let savedFileDescriptor = dup(fileDescriptor)
        defer { close(savedFileDescriptor) }

        let pipe = Pipe()
        dup2(pipe.fileHandleForWriting.fileDescriptor, fileDescriptor)

        // Drained concurrently: once the pipe buffer fills, a writer that nobody
        // is reading blocks, and the body under test would deadlock rather than
        // fail.
        // `availableData` rather than `read(upToCount:)`: this is a source target
        // with a lower deployment floor than the test targets that use it, and
        // the throwing form is macOS 10.15.4+. It blocks until data arrives and
        // returns empty at EOF, which is exactly the loop condition needed here.
        let drainTask = Task.detached { () -> Data in
            var accumulated = Data()
            while true {
                let chunk = pipe.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                accumulated.append(chunk)
            }
            return accumulated
        }

        func restore() async -> Data {
            fflush(stream)
            dup2(savedFileDescriptor, fileDescriptor)
            try? pipe.fileHandleForWriting.close()
            return await drainTask.value
        }

        do {
            try await body()
        } catch {
            _ = await restore()
            throw error
        }

        return String(decoding: await restore(), as: UTF8.self)
    }
}
