import Foundation
import ArgumentParser
import MachOKit
import MachOFoundation
import SwiftSectionKit
@_spi(Support) import SwiftIndexing
import SwiftPrinting
import SwiftInterface
import SwiftDeclarationRendering

/// Measures how long one image's Swift interface takes to index and to print,
/// read in-process (`MachOImage`) or offline (`MachOFile`), so the two readers
/// can be compared under one configuration in an ordinary process.
///
/// A test process is no place for this: swift-dependencies looks the test
/// context up with a `dlsym` on every `@Dependency` read there, which took half
/// of a rendering run's time and varies with how many images are loaded.
///
/// One run measures one reader once. Per-image caches outlive a pass, so a
/// second pass in the same process measures warm caches; repeat the process
/// instead.
@main
struct ReaderBenchmark: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reader-benchmark",
        abstract: "Times indexing and printing one image's Swift interface through MachOImage or MachOFile."
    )

    enum Reader: String, ExpressibleByArgument, CaseIterable {
        /// The image loaded into this process (`dlopen`), read through `MachOImage`.
        case image
        /// The image read from disk through `MachOFile`.
        case file
    }

    enum Mode: String, ExpressibleByArgument, CaseIterable {
        /// `SwiftDeclarationIndexer.prepare()` alone: what a host such as
        /// RuntimeViewer waits for while it loads an image.
        case index
        /// `SwiftInterfaceBuilder.prepare()` and `printRoot()`: what
        /// `swift-section interface` does.
        case interface
    }

    @Option(help: "The reader to measure.")
    var reader: Reader

    @Option(help: "What to measure.")
    var mode: Mode = .interface

    @Option(help: "The image to read: a framework name loaded into this process for `image`, an image of the running system's dyld shared cache for `file`.")
    var imageName: String?

    @Option(help: "A Mach-O file to read instead of a cache image (`file` only).")
    var filePath: String?

    @Option(name: .shortAndLong, help: "The slice of a fat file to read (`file` only).")
    var architecture: String?

    @Option(help: "A Mach-O file, a dyld cache file or a system root the file's dependencies are found in (`file` only, repeatable).")
    var dependencySearchPath: [String] = []

    @Flag(help: "Print the field offset, member address, vtable offset, witness table offset, type layout and enum layout comments, as RuntimeViewer does by default.")
    var layoutComments = false

    @Flag(help: "Index imported C types too, as RuntimeViewer does.")
    var showCImportedTypes = false

    @Option(help: "Write the printed interface to this path.")
    var outputPath: String?

    @Flag(help: "Report as one JSON object instead of a table.")
    var json = false

    func validate() throws {
        switch reader {
        case .image:
            guard imageName != nil else { throw ValidationError("`--reader image` needs `--image-name`.") }
            guard filePath == nil, architecture == nil, dependencySearchPath.isEmpty else {
                throw ValidationError("`--file-path`, `--architecture` and `--dependency-search-path` only apply to `--reader file`.")
            }
        case .file:
            guard (imageName == nil) != (filePath == nil) else {
                throw ValidationError("`--reader file` needs exactly one of `--image-name` and `--file-path`.")
            }
        }
    }

    func run() async throws {
        var measurements: [PhaseMeasurement] = []
        switch reader {
        case .image:
            let loading = ResourceSnapshot.now()
            let machOImage = try Self.loadImage(named: imageName ?? "")
            measurements.append(PhaseMeasurement(name: "load", from: loading, to: .now()))
            measurements += try await measure(machOImage, dependencySearchPaths: [])
        case .file:
            let searchPaths = dependencySearchPath.map { DependencySearchPath(classifyingPath: $0) }
            let loading = ResourceSnapshot.now()
            let source: MachOSource = if let filePath {
                .file(path: filePath, architecture: try architecture.map { try Self.parseArchitecture($0) })
            } else {
                .systemDyldSharedCache(image: .name(imageName ?? ""))
            }
            let machOFile = try source.load()
            measurements.append(PhaseMeasurement(name: "load", from: loading, to: .now()))
            measurements += try await Self.withAccessorThunkResolver(searchPaths: searchPaths) {
                try await measure(machOFile, dependencySearchPaths: searchPaths)
            }
        }
        report(measurements)
    }

    // MARK: - Measuring

    private func measure<MachO: MachOFieldLayoutRenderable>(
        _ machO: MachO,
        dependencySearchPaths: [DependencySearchPath]
    ) async throws -> [PhaseMeasurement] {
        let indexConfiguration = SwiftDeclarationIndexConfiguration(
            showCImportedTypes: showCImportedTypes,
            dependencySearchPaths: dependencySearchPaths + [.systemDyldSharedCache]
        )
        switch mode {
        case .index:
            let indexing = ResourceSnapshot.now()
            let indexer = SwiftDeclarationIndexer(configuration: indexConfiguration, in: machO)
            try await indexer.prepare()
            return [PhaseMeasurement(name: "index", from: indexing, to: .now())]
        case .interface:
            var printConfiguration = SwiftDeclarationPrintConfiguration()
            printConfiguration.printStrippedSymbolicItem = true
            printConfiguration.printFieldOffset = layoutComments
            printConfiguration.printMemberAddress = layoutComments
            printConfiguration.printVTableOffset = layoutComments
            printConfiguration.printPWTOffset = layoutComments
            printConfiguration.printTypeLayout = layoutComments
            printConfiguration.printEnumLayout = layoutComments
            if !dependencySearchPaths.isEmpty {
                // What `swift-section` does with the same paths: the named
                // ones first, the running system's cache as the fallback.
                printConfiguration.staticLayoutDependencyResolution = .dependencyClosure(searchPaths: dependencySearchPaths + [.systemDyldSharedCache])
            }
            let builder = try SwiftInterfaceBuilder(
                configuration: SwiftInterfaceBuilderConfiguration(indexConfiguration: indexConfiguration, printConfiguration: printConfiguration),
                in: machO
            )
            let preparing = ResourceSnapshot.now()
            try await builder.prepare()
            let printing = ResourceSnapshot.now()
            let interface = try await builder.printRoot().string
            let printed = ResourceSnapshot.now()
            if let outputPath {
                try interface.write(toFile: outputPath, atomically: true, encoding: .utf8)
            }
            return [
                PhaseMeasurement(name: "prepare", from: preparing, to: printing),
                PhaseMeasurement(name: "print", from: printing, to: printed, outputByteCount: interface.utf8.count),
            ]
        }
    }

    private static func withAccessorThunkResolver<Result>(
        searchPaths: [DependencySearchPath],
        _ operation: () async throws -> Result
    ) async throws -> Result {
        guard !searchPaths.isEmpty else { return try await operation() }
        return try await AccessorThunkResolution.$taskResolver.withValue(DisassemblingAccessorThunkResolver(searchPaths: searchPaths)) {
            try await operation()
        }
    }

    // MARK: - Loading

    /// Loads the framework into this process when it is not loaded yet, trying
    /// the public framework path, the private framework path and the bare name.
    private static func loadImage(named name: String) throws -> MachOImage {
        if let machOImage = MachOImage(name: name) { return machOImage }
        for candidatePath in [
            "/System/Library/Frameworks/\(name).framework/\(name)",
            "/System/Library/PrivateFrameworks/\(name).framework/\(name)",
            name,
        ] {
            _ = candidatePath.withCString { dlopen($0, RTLD_LAZY) }
            if let machOImage = MachOImage(name: name) { return machOImage }
        }
        throw ValidationError("`\(name)` could not be loaded into this process.")
    }

    private static func parseArchitecture(_ argument: String) throws -> Architecture {
        guard let architecture = Architecture(rawValue: argument) else {
            throw ValidationError("Unknown architecture `\(argument)`; expected one of \(Architecture.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        return architecture
    }

    // MARK: - Reporting

    private func report(_ measurements: [PhaseMeasurement]) {
        let peakFootprint = ResourceSnapshot.now().lifetimePeakFootprintBytes
        if json {
            let phases = measurements.map { measurement -> [String: Any] in
                var phase: [String: Any] = [
                    "name": measurement.name,
                    "wallSeconds": measurement.wallSeconds,
                    "processorSeconds": measurement.processorSeconds,
                    "instructions": measurement.instructions,
                ]
                if let outputByteCount = measurement.outputByteCount { phase["outputBytes"] = outputByteCount }
                return phase
            }
            let document: [String: Any] = [
                "reader": reader.rawValue,
                "mode": mode.rawValue,
                "layoutComments": layoutComments,
                "phases": phases,
                "peakFootprintBytes": peakFootprint,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: document, options: [.sortedKeys]),
               let text = String(data: data, encoding: .utf8) {
                print(text)
            }
            return
        }
        print("reader \(reader.rawValue), mode \(mode.rawValue), layout comments \(layoutComments ? "on" : "off")")
        for measurement in measurements {
            var line = "  \(measurement.name.padding(toLength: 8, withPad: " ", startingAt: 0))"
            line += String(format: " wall %8.3f s  cpu %8.3f s  instructions %8.3f G", measurement.wallSeconds, measurement.processorSeconds, Double(measurement.instructions) / 1e9)
            if let outputByteCount = measurement.outputByteCount { line += "  output \(outputByteCount) bytes" }
            print(line)
        }
        print(String(format: "  peak footprint %.1f MB", Double(peakFootprint) / 1_048_576))
    }
}

// MARK: - Resource usage

/// The process's resource usage at one moment. Processor time is summed over
/// every thread, so a phase that runs on several threads reports more
/// processor time than wall time.
private struct ResourceSnapshot {
    let wallClockNanoseconds: UInt64
    let processorSeconds: Double
    let instructions: UInt64
    let lifetimePeakFootprintBytes: UInt64

    static func now() -> ResourceSnapshot {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let processorSeconds = Self.seconds(of: usage.ru_utime) + Self.seconds(of: usage.ru_stime)

        var usageInformation = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &usageInformation) { pointer in
            pointer.withMemoryRebound(to: Optional<rusage_info_t>.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        return ResourceSnapshot(
            wallClockNanoseconds: clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW),
            processorSeconds: processorSeconds,
            instructions: status == 0 ? usageInformation.ri_instructions : 0,
            lifetimePeakFootprintBytes: status == 0 ? usageInformation.ri_lifetime_max_phys_footprint : 0
        )
    }

    private static func seconds(of time: timeval) -> Double {
        Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000
    }
}

private struct PhaseMeasurement {
    let name: String
    let wallSeconds: Double
    let processorSeconds: Double
    let instructions: UInt64
    let outputByteCount: Int?

    init(name: String, from start: ResourceSnapshot, to end: ResourceSnapshot, outputByteCount: Int? = nil) {
        self.name = name
        self.wallSeconds = Double(end.wallClockNanoseconds - start.wallClockNanoseconds) / 1e9
        self.processorSeconds = end.processorSeconds - start.processorSeconds
        self.instructions = end.instructions &- start.instructions
        self.outputByteCount = outputByteCount
    }
}
