import Foundation
import Testing
import ArgumentParser
import MachOFoundation
import SwiftSectionKit
@testable import swift_section

/// The wrapper's one job besides wording and streams: turning flags into the
/// library request. A flag that stops reaching its field produces a
/// plausible-looking but wrong product, so each mapping is pinned from the
/// parsed command to the request it makes.
@Suite
struct CommandRequestMappingTests {
    // MARK: - Input options

    @Test("A path alone is a file, with the architecture for a fat binary's slice")
    func fileInput() throws {
        let request = try DumpCommand.parse(["/tmp/Sample", "-a", "arm64e"]).makeRequest()
        #expect(request.source == .file(path: "/tmp/Sample", architecture: .arm64e))
    }

    @Test("--dyld-shared-cache extracts the named image from the cache at the path")
    func cacheInput() throws {
        let request = try DumpCommand.parse(["/tmp/dyld_shared_cache_arm64e", "--dyld-shared-cache", "-n", "SwiftUICore"]).makeRequest()
        #expect(request.source == .dyldSharedCache(cachePath: "/tmp/dyld_shared_cache_arm64e", image: .name("SwiftUICore")))
    }

    @Test("--uses-system-dyld-shared-cache needs no path")
    func systemCacheInput() throws {
        let request = try InterfaceCommand.parse(["--uses-system-dyld-shared-cache", "-p", "/usr/lib/libobjc.A.dylib"]).makeRequest()
        #expect(request.source == .systemDyldSharedCache(image: .path("/usr/lib/libobjc.A.dylib")))
    }

    /// These combinations have no `MachOSource`; they keep the wording the
    /// command line has always printed for them.
    @Test("Input combinations a source cannot express keep their historical errors", arguments: [
        (["--dyld-shared-cache", "-n", "Foundation"], "The filePath is required"),
        (["/tmp/cache", "--dyld-shared-cache", "-n", "Foundation", "-p", "/usr/lib/libobjc.A.dylib"], "Both cacheImageName and cacheImagePath are provided"),
        (["/tmp/cache", "--dyld-shared-cache"], "Either cacheImageName or cacheImagePath must be provided"),
        ([], "The filePath is required"),
    ])
    func impossibleInputCombinations(arguments: [String], messagePrefix: String) throws {
        let command = try DumpCommand.parse(arguments)
        #expect(performing: { _ = try command.makeRequest() }, throws: { error in
            (error as? SwiftSectionCommandError)?.errorDescription?.hasPrefix(messagePrefix) == true
        })
    }

    @Test("--dependency-search-path is classified into search paths")
    func dependencySearchPaths() throws {
        let directoryPath = FileManager.default.temporaryDirectory.path
        let request = try DumpCommand.parse(["/tmp/Sample", "--dependency-search-path", directoryPath]).makeRequest()
        #expect(request.dependencySearchPaths == [DependencySearchPath(classifyingPath: directoryPath)])
    }

    // MARK: - dump

    @Test("dump defaults: every section, section order, no comments, to the output")
    func dumpDefaults() throws {
        let request = try DumpCommand.parse(["/tmp/Sample"]).makeRequest()
        #expect(request == DumpRequest(source: .file(path: "/tmp/Sample", architecture: nil)))
    }

    @Test("dump flags reach their fields")
    func dumpFlags() throws {
        let request = try DumpCommand.parse([
            "/tmp/Sample",
            "--sections", "protocols", "types",
            "--preferred-binary-order",
            "--emit-expanded-field-offsets",
            "--emit-member-addresses", "--emit-vtable-offsets", "--emit-pwt-addresses",
            "--emit-type-layout", "--emit-enum-layout", "--emit-export-status", "--emit-header",
            "--output-path", "out.txt",
        ]).makeRequest()
        #expect(request.sections == .only([.protocols, .types]))
        #expect(request.ordering == .binaryOrder)
        #expect(request.fieldOffsetComments == .expanded)
        #expect(request.emitsMemberAddresses)
        #expect(request.emitsVTableOffsets)
        #expect(request.emitsProtocolWitnessTableAddresses)
        #expect(request.emitsTypeLayout)
        #expect(request.emitsEnumLayout)
        #expect(request.emitsExportStatus)
        #expect(request.emitsHeader)
        #expect(request.destination == .file(path: "out.txt"))
    }

    @Test("--emit-field-offsets alone is the flat form")
    func dumpFlatFieldOffsets() throws {
        #expect(try DumpCommand.parse(["/tmp/Sample", "--emit-field-offsets"]).makeRequest().fieldOffsetComments == .flat)
    }

    @Test("A comment template reaches the request as a configuration")
    func dumpCommentTemplates() throws {
        let request = try DumpCommand.parse(["/tmp/Sample", "--member-address-template", "${offset}"]).makeRequest()
        #expect(request.commentTransformers?.swiftMemberAddress.isEnabled == true)
        #expect(request.commentTransformers?.swiftMemberAddress.template == "${offset}")
    }

    // MARK: - interface

    @Test("interface flags reach their fields")
    func interfaceFlags() throws {
        let request = try InterfaceCommand.parse([
            "/tmp/Sample",
            "--show-c-imported-types", "--parse-opaque-return-type",
            "--resolve-c-module-names", "--supplementary-apinotes", "/tmp/Extra.apinotes",
            "--emit-offset-comments", "--sort-members-by-offset", "--exported-only",
            "--infer-objc-overrides", "--emit-header",
        ]).makeRequest()
        #expect(request.showsCImportedTypes)
        #expect(request.parsesOpaqueReturnTypes)
        #expect(request.cModuleNameResolution == .enabled(supplementaryAPINotesPaths: ["/tmp/Extra.apinotes"]))
        #expect(request.fieldOffsetComments == .flat)
        #expect(request.memberSortOrder == .byOffset)
        #expect(request.printsExportedDeclarationsOnly)
        #expect(request.infersObjCOverridesFromSelectorNames)
        #expect(request.emitsHeader)
    }

    @Test("--emit-expanded-field-offsets implies the offset comments")
    func interfaceExpandedFieldOffsets() throws {
        #expect(try InterfaceCommand.parse(["/tmp/Sample", "--emit-expanded-field-offsets"]).makeRequest().fieldOffsetComments == .expanded)
    }

    // MARK: - snapshot / diff / evolution

    @Test("snapshot without a path is a usage error")
    func snapshotRequiresAPath() throws {
        let command = try SnapshotCommand.parse([])
        #expect(throws: ValidationError.self) { try command.makeRequest() }
    }

    @Test("snapshot with --dyld-shared-cache extracts the named image from each binary input")
    func snapshotCacheInput() throws {
        let request = try SnapshotCommand.parse(["/tmp/cache", "--dyld-shared-cache", "-p", "/usr/lib/libobjc.A.dylib", "--label", "26.0"]).makeRequest()
        #expect(request == ABISnapshotRequest(
            source: .path("/tmp/cache"),
            binaryLoading: BinaryLoadingOptions(dyldSharedCacheImage: .path("/usr/lib/libobjc.A.dylib")),
            label: "26.0"
        ))
    }

    @Test("diff's output flags become one report", arguments: [
        ([String](), ABIDiffRequest.Report.changeList),
        (["--summary-only"], .summary),
        (["--json"], .json),
        (["--interface"], .annotatedInterface(format: .inline, includesBreakingChangeVerdict: false)),
        (["--interface", "--format", "unified", "--fail-on-breaking"], .annotatedInterface(format: .unified, includesBreakingChangeVerdict: true)),
        (["--interface", "--format", "markdown"], .annotatedInterface(format: .markdownFenced, includesBreakingChangeVerdict: false)),
    ])
    func diffReport(flags: [String], expectedReport: ABIDiffRequest.Report) throws {
        #expect(try DiffCommand.parse(flags + ["old.dylib", "new.dylib"]).makeRequest().report == expectedReport)
    }

    @Test("diff over two caches extracts the same image from each")
    func diffCacheInputs() throws {
        let request = try DiffCommand.parse(["--dyld-shared-cache", "-n", "SwiftUICore", "--jobs", "1", "old", "new"]).makeRequest()
        #expect(request == ABIDiffRequest(
            old: .path("old"),
            new: .path("new"),
            binaryLoading: BinaryLoadingOptions(dyldSharedCacheImage: .name("SwiftUICore")),
            maximumConcurrentPreparations: 1
        ))
    }

    /// Empty labels are kept, so that a stray comma fails the one-label-per-
    /// input check instead of shifting every later label.
    @Test("evolution's --labels splits on commas, trims, and keeps empty labels")
    func evolutionLabels() throws {
        let request = try EvolutionCommand.parse(["--labels", " 17.0 ,,26.0", "a", "b", "c"]).makeRequest()
        #expect(request.labels == ["17.0", "", "26.0"])
        #expect(request.inputs == [.path("a"), .path("b"), .path("c")])
        #expect(request.report == .lineage)
    }

    @Test("evolution's output flags become one report", arguments: [
        ([String](), ABIEvolutionRequest.Report.lineage),
        (["--summary-only"], .summary),
        (["--json"], .json),
        (["--interface"], .annotatedInterface(availabilityAttributes: .none)),
        (["--interface", "--emit-available"], .annotatedInterface(availabilityAttributes: .inferredPlatform)),
        (["--interface", "--emit-available", "--platform", "iOS"], .annotatedInterface(availabilityAttributes: .platform("iOS"))),
    ])
    func evolutionReport(flags: [String], expectedReport: ABIEvolutionRequest.Report) throws {
        #expect(try EvolutionCommand.parse(flags + ["old.dylib", "new.dylib"]).makeRequest().report == expectedReport)
    }

    // MARK: - objc

    @Test("objc dump passes the image description the caller typed")
    func objcDumpImageDescription() throws {
        let request = try ObjCDumpCommand.parse(["/tmp/cache", "--dyld-shared-cache", "-n", "AppKit", "--sections", "classes,protocols", "--verbose"]).makeRequest()
        #expect(request.source == .dyldSharedCache(cachePath: "/tmp/cache", image: .name("AppKit")))
        #expect(request.imageDescription == "AppKit")
        #expect(request.kinds == [.classes, .protocols])
        #expect(request.reportsIndexingProgress)
    }

    @Test("objc diff's output flags become one report", arguments: [
        ([String](), ObjCAPIDiffRequest.Report.changeList),
        (["--summary-only"], .summary),
        (["--json"], .json),
    ])
    func objcDiffReport(flags: [String], expectedReport: ObjCAPIDiffRequest.Report) throws {
        #expect(try ObjCDiffCommand.parse(flags + ["old.dylib", "new.dylib"]).makeRequest().report == expectedReport)
    }

    @Test("objc evolution splits --labels the way evolution does")
    func objcEvolutionLabels() throws {
        let request = try ObjCEvolutionCommand.parse(["--labels", "a, b", "--json", "one", "two"]).makeRequest()
        #expect(request.labels == ["a", "b"])
        #expect(request.report == .json)
    }
}
