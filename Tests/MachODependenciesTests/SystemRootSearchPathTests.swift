import Foundation
import MachOKit
import MachOFixtureSupport
import Testing
@testable import MachODependencies

/// `DependencySearchPath.systemRoot` and the inference of search paths from
/// a root binary's own location.
///
/// A system root is a directory tree an absolute load name is resolved
/// under — an iOS 26 or earlier simulator runtime's `RuntimeRoot`, where
/// `/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore` is a file.
/// From iOS 27 beta 3 on the runtime ships a `dyld_sim_shared_cache_arm64`
/// instead, so inference looks for a cache first and takes the root only
/// when the file's path ends with its own install name.
@Suite
struct SystemRootSearchPathTests {
    private func temporaryDirectory(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// The fixture framework, reached through the path it was loaded from.
    private func fixtureURL() throws -> URL {
        switch try loadFromFile(named: .SymbolTestsCore) {
        case .machO(let machOFile):
            return machOFile.url
        case .fat(let fatFile):
            return try #require(try fatFile.machOFiles().first).url
        }
    }

    @Test func aSystemRootResolvesAbsoluteLoadNamesUnderIt() throws {
        let root = try temporaryDirectory(named: "SystemRoot")
        defer { try? FileManager.default.removeItem(at: root) }
        let loadName = "/System/Library/Frameworks/Probe.framework/Probe"
        let probeURL = root.appendingPathComponent(String(loadName.dropFirst()))
        try FileManager.default.createDirectory(at: probeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: probeURL, withDestinationURL: fixtureURL())

        let locator = FileDependencyLocator(searchPaths: [.systemRoot(path: root.path)])
        #expect(locator.loadFailures.isEmpty)
        let located = try #require(locator.locate(loadName: loadName))
        #expect(located.url.path == probeURL.path)
        // Only absolute load names are joined onto the root.
        #expect(locator.locate(loadName: "@rpath/Probe.framework/Probe") == nil)
        #expect(locator.locate(loadName: "/System/Library/Frameworks/Missing.framework/Missing") == nil)
    }

    @Test func aSystemRootThatIsNotADirectoryIsAReportedFailure() throws {
        let root = try temporaryDirectory(named: "SystemRootFile")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("not-a-directory")
        try Data().write(to: file)

        let locator = FileDependencyLocator(searchPaths: [.systemRoot(path: file.path)])
        #expect(locator.loadFailures.count == 1)
        #expect(locator.loadFailures.first?.error as? DependencySearchPathError == .systemRootIsNotADirectory(path: file.path))
    }

    @Test func inferenceTakesARuntimeRootsOwnCacheForTheRootsArchitecture() throws {
        let runtimeRoot = try temporaryDirectory(named: "RuntimeRoot")
        defer { try? FileManager.default.removeItem(at: runtimeRoot) }
        let cacheDirectory = runtimeRoot.appendingPathComponent("System/Library/Caches/com.apple.dyld")
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        for fileName in ["dyld_sim_shared_cache_arm64", "dyld_sim_shared_cache_arm64.01", "dyld_sim_shared_cache_arm64.map", "dyld_sim_shared_cache_arm64.atlas", "dyld_sim_shared_cache_x86_64"] {
            try Data().write(to: cacheDirectory.appendingPathComponent(fileName))
        }
        let rootFile = runtimeRoot.appendingPathComponent("usr/lib/libProbe.dylib")

        let forArm64 = DependencySearchPath.inferred(forRootFileAt: rootFile, installName: "/usr/lib/libProbe.dylib", architectureName: "arm64")
        #expect(forArm64 == [.dyldSharedCache(path: cacheDirectory.appendingPathComponent("dyld_sim_shared_cache_arm64").path)])

        let forAnyArchitecture = DependencySearchPath.inferred(forRootFileAt: rootFile, installName: "/usr/lib/libProbe.dylib", architectureName: nil)
        #expect(forAnyArchitecture == [
            .dyldSharedCache(path: cacheDirectory.appendingPathComponent("dyld_sim_shared_cache_arm64").path),
            .dyldSharedCache(path: cacheDirectory.appendingPathComponent("dyld_sim_shared_cache_x86_64").path),
        ])
    }

    @Test func inferenceFallsBackToTheInstallNamePrefix() throws {
        let root = try temporaryDirectory(named: "FrameworkRoot")
        defer { try? FileManager.default.removeItem(at: root) }
        let installName = "/System/Library/Frameworks/Probe.framework/Probe"
        let rootFile = root.appendingPathComponent(String(installName.dropFirst()))

        #expect(DependencySearchPath.inferred(forRootFileAt: rootFile, installName: installName, architectureName: "arm64") == [.systemRoot(path: root.path)])
        // A relative install name says nothing about the tree the file sits in.
        #expect(DependencySearchPath.inferred(forRootFileAt: rootFile, installName: "@rpath/Probe.framework/Probe", architectureName: "arm64").isEmpty)
        // A file whose path does not end with its install name is not a system tree either.
        #expect(DependencySearchPath.inferred(forRootFileAt: root.appendingPathComponent("Probe"), installName: installName, architectureName: "arm64").isEmpty)
    }

    @Test func onlyAMainCacheFileNameCountsAsACache() {
        #expect(DependencySearchPath.isMainCacheFileName("dyld_shared_cache_arm64e", architectureName: nil))
        #expect(DependencySearchPath.isMainCacheFileName("dyld_sim_shared_cache_arm64", architectureName: "arm64"))
        #expect(!DependencySearchPath.isMainCacheFileName("dyld_sim_shared_cache_arm64", architectureName: "arm64e"))
        #expect(!DependencySearchPath.isMainCacheFileName("dyld_shared_cache_arm64e.01", architectureName: nil))
        #expect(!DependencySearchPath.isMainCacheFileName("dyld_shared_cache_arm64e.map", architectureName: nil))
        #expect(!DependencySearchPath.isMainCacheFileName("dyld_shared_cache_", architectureName: nil))
        #expect(!DependencySearchPath.isMainCacheFileName("libswiftCore.dylib", architectureName: nil))
    }

    @Test func classifyingAPathPicksTheKindByItsShape() throws {
        let directory = try temporaryDirectory(named: "Classify")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cacheFile = directory.appendingPathComponent("dyld_sim_shared_cache_arm64")
        try Data().write(to: cacheFile)
        let otherFile = directory.appendingPathComponent("libProbe.dylib")
        try Data().write(to: otherFile)

        #expect(DependencySearchPath(classifyingPath: directory.path) == .systemRoot(path: directory.path))
        #expect(DependencySearchPath(classifyingPath: cacheFile.path) == .dyldSharedCache(path: cacheFile.path))
        #expect(DependencySearchPath(classifyingPath: otherFile.path) == .machOFile(path: otherFile.path))
    }
}
