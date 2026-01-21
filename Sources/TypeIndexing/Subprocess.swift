#if os(macOS)

import Foundation

struct Subprocess: Codable {
    // MARK: - Open Stored Properties

    /// The URL to the receiver’s executable.
    var executableURL: URL
    /// The arguments that should be used to launch the executable.
    var arguments: [String]?
    /// The environment for the receiver.
    ///
    /// If `nil`, the environment is inherited from the process that created the receiver.
    var environment: [String: String]?
    /// The current directory for the receiver.
    ///
    /// If `nil`, the current directory is inherited from the process that created the receiver.
    var currentDirectoryURL: URL?
    /// Whether the standard error should also be piped to the output.
    var shouldPipeStandardError: Bool = false

    // MARK: - Internal Computed Properties

    /// Initializes a `Process` with the subprocess's properties.
    var process: Process {
        let process = Process()

        if #available(OSX 10.13, *) {
            process.executableURL = executableURL
        } else {
            process.launchPath = executableURL.absoluteString
        }

        if let arguments = arguments {
            process.arguments = arguments
        }

        if let environment = environment {
            process.environment = environment
        }

        if let currentDirectoryURL = currentDirectoryURL {
            if #available(OSX 10.13, *) {
                process.currentDirectoryURL = currentDirectoryURL
            } else {
                process.currentDirectoryPath = currentDirectoryURL.absoluteString
            }
        }

        return process
    }

    // MARK: - Public Initializers

    init(executableURL: URL) {
        self.executableURL = executableURL
    }

    // MARK: - Subprocess Methods

    static func xcRun(arguments: [String]) -> String? {
        var subprocess = Subprocess(executableURL: URL(fileURLWithPath: "/usr/bin/xcrun", isDirectory: false))
        subprocess.arguments = arguments
        return launch(subprocess: subprocess)
    }

    static func xcodeBuild(arguments: [String], currentDirectoryURL: URL) -> String? {
        var subprocess = Subprocess(executableURL: URL(fileURLWithPath: "/usr/bin/xcodebuild", isDirectory: false))
        subprocess.arguments = arguments + [
            "clean",
            "build",
            "CODE_SIGN_IDENTITY=",
            "CODE_SIGNING_REQUIRED=NO",
        ]
        subprocess.currentDirectoryURL = currentDirectoryURL
        subprocess.shouldPipeStandardError = true
        return launch(subprocess: subprocess)
    }

    static func executeBash(_ command: String, currentDirectoryURL: URL? = nil) -> String? {
        var subprocess = Subprocess(executableURL: URL(fileURLWithPath: "/bin/bash", isDirectory: false))
        subprocess.arguments = ["-c", command]
        subprocess.currentDirectoryURL = currentDirectoryURL
        return launch(subprocess: subprocess)
    }

    static func launch(subprocess: Subprocess) -> String? {
        let process = subprocess.process

        let pipe = Pipe()
        process.standardOutput = pipe
        if subprocess.shouldPipeStandardError {
            process.standardError = pipe
        }

        process.launch()

        let file = pipe.fileHandleForReading
        defer { file.closeFile() }

        let data = file.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#endif
