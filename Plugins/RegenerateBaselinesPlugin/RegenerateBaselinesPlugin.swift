import Foundation
import PackagePlugin

/// `swift package regen-baselines [--suite <Name>] [--output <Path>]`
///
/// Builds and invokes the `baseline-generator` executable target to regenerate
/// the auto-generated `__Baseline__/<File>Baseline.swift` files consumed by
/// the fixture-based test coverage suites under
/// `Tests/MachOSwiftSectionTests/Fixtures/`.
///
/// Replaces the legacy `Scripts/regen-baselines.sh` wrapper. Differences:
///   - The default `--output` resolves against `context.package.directoryURL`,
///     so the command works from any working directory (Xcode's plugin runner
///     does not chdir to the package root).
///   - Write access to the package directory is declared up-front via
///     `permissions: [.writeToPackageDirectory(reason:)]`, so both `swift
///     package` and Xcode prompt the user before writing baselines.
///
/// All command-line arguments are forwarded verbatim to `baseline-generator`,
/// which uses `swift-argument-parser` and accepts `--suite`/`--output`.
@main
struct RegenerateBaselinesPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let baselineGeneratorTool = try context.tool(named: "baseline-generator")

        var forwardedArguments = arguments
        if !userProvidedOutputArgument(in: forwardedArguments) {
            let defaultOutputURL = context.package.directoryURL
                .appending(path: "Tests/MachOSwiftSectionTests/Fixtures/__Baseline__")
            forwardedArguments.append(contentsOf: ["--output", defaultOutputURL.path()])
        }

        // Capture stdout/stderr via pipes and re-emit through the plugin's own
        // file handles. SwiftPM's plugin sandbox silently drops direct stdio
        // inheritance from child processes, so the bytes have to be copied
        // explicitly. The synchronous read after `waitUntilExit` is safe for
        // `baseline-generator` because its output (only ArgumentParser errors
        // and the occasional throw trace) stays well below the OS pipe
        // buffer; if that ever changes, switch to streaming via a detached
        // forwarding Task.
        let standardOutputPipe = Pipe()
        let standardErrorPipe = Pipe()

        let baselineProcess = Process()
        baselineProcess.executableURL = baselineGeneratorTool.url
        baselineProcess.arguments = forwardedArguments
        baselineProcess.standardOutput = standardOutputPipe
        baselineProcess.standardError = standardErrorPipe

        try baselineProcess.run()
        baselineProcess.waitUntilExit()

        let standardOutputData = standardOutputPipe.fileHandleForReading.readDataToEndOfFile()
        let standardErrorData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
        if !standardOutputData.isEmpty {
            try FileHandle.standardOutput.write(contentsOf: standardOutputData)
        }
        if !standardErrorData.isEmpty {
            try FileHandle.standardError.write(contentsOf: standardErrorData)
        }

        guard baselineProcess.terminationStatus == 0 else {
            throw RegenerateBaselinesPluginError.subprocessFailed(status: baselineProcess.terminationStatus)
        }
    }

    private func userProvidedOutputArgument(in arguments: [String]) -> Bool {
        arguments.contains(where: { $0 == "--output" || $0.hasPrefix("--output=") })
    }
}

enum RegenerateBaselinesPluginError: Error, CustomStringConvertible {
    case subprocessFailed(status: Int32)

    var description: String {
        switch self {
        case .subprocessFailed(let status):
            return "baseline-generator exited with status \(status)"
        }
    }
}
