#if os(macOS)

import Foundation

/// Minimal synchronous subprocess helper for the developer-tool lookups the
/// indexer needs (`xcode-select`, `xcrun`). Not a general process runner.
enum Subprocess {
    enum Error: Swift.Error, CustomStringConvertible {
        case nonZeroTermination(executablePath: String, arguments: [String], terminationStatus: Int32)
        case unreadableOutput(executablePath: String, arguments: [String])

        var description: String {
            switch self {
            case .nonZeroTermination(let executablePath, let arguments, let terminationStatus):
                return "\(executablePath) \(arguments.joined(separator: " ")) exited with status \(terminationStatus)"
            case .unreadableOutput(let executablePath, let arguments):
                return "\(executablePath) \(arguments.joined(separator: " ")) produced non-UTF-8 output"
            }
        }
    }

    /// Runs `executablePath` with `arguments` and returns its trimmed standard
    /// output. Throws when the process exits non-zero or prints non-UTF-8.
    static func output(of executablePath: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let standardOutputPipe = Pipe()
        process.standardOutput = standardOutputPipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let outputData = standardOutputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Error.nonZeroTermination(executablePath: executablePath, arguments: arguments, terminationStatus: process.terminationStatus)
        }
        guard let outputString = String(data: outputData, encoding: .utf8) else {
            throw Error.unreadableOutput(executablePath: executablePath, arguments: arguments)
        }
        return outputString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func xcrun(_ arguments: [String]) throws -> String {
        try output(of: "/usr/bin/xcrun", arguments: arguments)
    }

    /// The active developer directory (`xcode-select -p`), e.g.
    /// `/Applications/Xcode.app/Contents/Developer`.
    static func activeDeveloperDirectory() throws -> String {
        try output(of: "/usr/bin/xcode-select", arguments: ["-p"])
    }
}

#endif
