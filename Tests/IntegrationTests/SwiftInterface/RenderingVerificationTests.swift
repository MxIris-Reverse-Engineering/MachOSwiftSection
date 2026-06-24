import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftDump
import SwiftDeclarationRendering
import SwiftInterface
import MachOFixtureSupport
import Demangling

/// Maintainer-only rendering-verification harness (no assertions — like the rest
/// of `IntegrationTests`).
///
/// Regenerates, for a configurable set of frameworks, **both** the `SwiftDump`
/// dumper output (`TypeContextWrapper.dumper(...).body`, metadata-aware via the
/// factory) and the `SwiftPrinting` interface output (`SwiftInterfaceBuilder`),
/// through **both** readers — MachOFile (from the dyld shared cache) and
/// MachOImage (in-process) — with every metadata option enabled, writing each to
/// `$RV_OUT/<dump|interface>-<framework>-<reader>.txt`.
///
/// Intended use: run on two checkouts (or before/after a change) and `diff` the
/// two output directories to confirm the dump / interface rendering is
/// unchanged. Nothing is asserted.
///
/// Environment:
///   - `RV_OUT`         output directory (default: a `macho-rendering-verification`
///                      folder under the system temp dir).
///   - `RV_FRAMEWORKS`  comma-separated framework names (default `SwiftUI,SwiftUICore`).
///   - `RV_OPTS`        comma-separated options (default = all):
///                      `fieldOffset, expandedFieldOffsets, typeLayout, enumLayout,
///                      spareBitAnalysis, memberAddress, vtableOffset, pwtOffset`.
///
/// Caveat: `expandedFieldOffsets` over a MachOImage of a framework with very
/// deeply nested generic types (e.g. SwiftUI) hits a pre-existing stack overflow
/// in the static generic-parameter substitution; drop it via `RV_OPTS` to avoid.
@Suite(.serialized)
@MainActor
struct RenderingVerificationTests {
    private static var outputDirectory: String {
        ProcessInfo.processInfo.environment["RV_OUT"]
            ?? NSTemporaryDirectory() + "macho-rendering-verification"
    }

    private static var frameworks: [String] {
        let raw = ProcessInfo.processInfo.environment["RV_FRAMEWORKS"] ?? "SwiftUI,SwiftUICore"
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static var options: Set<String> {
        let raw = ProcessInfo.processInfo.environment["RV_OPTS"]
            ?? "fieldOffset,expandedFieldOffsets,typeLayout,enumLayout,spareBitAnalysis,memberAddress,vtableOffset,pwtOffset"
        return Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    @Test
    func generate() async throws {
        let options = Self.options
        for framework in Self.frameworks {
            if let image = Self.inProcessImage(named: framework) {
                try write(await renderDump(in: image, options: options), to: "dump-\(framework)-image")
                try write(await renderInterface(in: image, options: options), to: "interface-\(framework)-image")
            } else {
                print("[RV] skipped \(framework) image: not loadable in-process")
            }

            if let file = Self.cacheFile(named: framework) {
                try write(await renderDump(in: file, options: options), to: "dump-\(framework)-file")
                try write(await renderInterface(in: file, options: options), to: "interface-\(framework)-file")
            } else {
                print("[RV] skipped \(framework) file: not found in dyld shared cache")
            }
        }
    }

    // MARK: - Fixture loading

    /// dlopen a framework (so `MachOImage(name:)` can find it in-process) and wrap
    /// it. Tries the public framework path, the private framework path, and the
    /// bare leaf name so most system frameworks resolve without configuration.
    private static func inProcessImage(named framework: String) -> MachOImage? {
        if MachOImage(name: framework) == nil {
            for candidate in [
                "/System/Library/Frameworks/\(framework).framework/\(framework)",
                "/System/Library/PrivateFrameworks/\(framework).framework/\(framework)",
                framework,
            ] {
                _ = candidate.withCString { dlopen($0, RTLD_LAZY) }
                if MachOImage(name: framework) != nil { break }
            }
        }
        return MachOImage(name: framework)
    }

    private static func cacheFile(named framework: String) -> MachOFile? {
        guard let cache = try? FullDyldCache(path: .current) else { return nil }
        return cache.machOFile(by: .name(framework))
    }

    // MARK: - Renderers

    private func renderInterface(in machO: some FieldLayoutRenderable, options: Set<String>) async throws -> String {
        var configuration = SwiftInterfaceBuilderConfiguration()
        configuration.printConfiguration.printFieldOffset = options.contains("fieldOffset")
        configuration.printConfiguration.printExpandedFieldOffsets = options.contains("expandedFieldOffsets")
        configuration.printConfiguration.printTypeLayout = options.contains("typeLayout")
        configuration.printConfiguration.printEnumLayout = options.contains("enumLayout")
        configuration.printConfiguration.printMemberAddress = options.contains("memberAddress")
        configuration.printConfiguration.printVTableOffset = options.contains("vtableOffset")
        configuration.printConfiguration.printPWTOffset = options.contains("pwtOffset")
        let builder = try SwiftInterfaceBuilder(configuration: configuration, in: machO)
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    private func renderDump(in machO: some FieldLayoutRenderable, options: Set<String>) async throws -> String {
        var configuration = DumperConfiguration(demangleResolver: .using(options: .test))
        configuration.printFieldOffset = options.contains("fieldOffset")
        configuration.printExpandedFieldOffsets = options.contains("expandedFieldOffsets")
        configuration.printTypeLayout = options.contains("typeLayout")
        configuration.printEnumLayout = options.contains("enumLayout")
        configuration.printSpareBitAnalysis = options.contains("spareBitAnalysis")
        configuration.printMemberAddress = options.contains("memberAddress")
        configuration.printVTableOffset = options.contains("vtableOffset")
        configuration.printConformancePWTAddress = options.contains("pwtOffset")
        var results: [String] = []
        for typeWrapper in try machO.swift.types {
            do {
                results.append(try await typeWrapper.dumper(using: configuration, in: machO).body.string)
            } catch {
                results.append("Error: \(error)")
            }
        }
        return results.joined(separator: "\n")
    }

    private func write(_ text: String, to name: String) throws {
        let directory = Self.outputDirectory
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let path = "\(directory)/\(name).txt"
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        print("[RV] wrote \(name): \(text.utf8.count) bytes -> \(path)")
    }
}
