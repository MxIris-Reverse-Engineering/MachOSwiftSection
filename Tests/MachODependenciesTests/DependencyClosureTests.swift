import Foundation
import MachOFixtureSupport
import MachOKit
import MachOKitExtensions
import Testing
@testable import MachODependencies
@testable import MachOTestingSupport

/// Covers the traversal contract of `DependencyClosure` on the
/// `SymbolTestsCore` fixture, whose load commands mix every shape the
/// locators must handle: an `@rpath` sibling framework (`SymbolTestsHelper`,
/// resolvable in-process and through an explicit file, never through the
/// cache), absolute system frameworks (`Foundation`), and absolute Swift
/// runtime dylibs, some weakly linked and not necessarily mapped in the test
/// process.
///
/// Declares `SymbolTestsHelper` because the offline closure reaches that
/// binary by a hand-built path — the sharing rule is about every suite that
/// touches the image, not only the ones asserting on its caches.
@Suite(ExclusiveImageAccess(.SymbolTestsHelper))
final class DependencyClosureTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    /// On-disk path of the helper framework binary, derived from this file's
    /// location: a `MachOFile`'s `imagePath` is its install name
    /// (`@rpath/…`), so the explicit search path cannot come from the root.
    private static let symbolTestsHelperOnDiskPath: String = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/MachODependenciesTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repository root
            .appendingPathComponent("Tests/Projects/SymbolTests/DerivedData/SymbolTests/Build/Products/Release/SymbolTestsHelper.framework/Versions/A/SymbolTestsHelper")
            .standardizedFileURL.path
    }()

    private static let symbolTestsHelperLoadName = "@rpath/SymbolTestsHelper.framework/Versions/A/SymbolTestsHelper"
    private static let swiftCoreLoadName = "/usr/lib/swift/libswiftCore.dylib"

    private func bareImageNames<MachO: MachORepresentableWithCache>(of images: [MachO]) -> [String] {
        images.map { DependencyLoadName.bareImageName(of: $0.imagePath) }
    }

    private func directLoadNameBareImageNames<MachO: MachORepresentableWithCache>(of root: MachO) -> [String] {
        var seen: Set<String> = []
        return root.dependencies.map { DependencyLoadName.bareImageName(of: $0.dylib.name) }.filter { seen.insert($0).inserted }
    }

    // MARK: - In-process

    /// The image initializer must resolve the dependencies dyld has mapped —
    /// including the ones linked by absolute path, which only resolve once
    /// the load name is normalized to a bare name.
    @MainActor
    @Test func inProcessDirectClosureResolvesMappedDependencies() throws {
        let root = machOImage
        let closure = DependencyClosure(root: root, traversal: .direct)

        let resolvedBareImageNames = bareImageNames(of: closure.images)
        #expect(resolvedBareImageNames.contains("SymbolTestsHelper"), "the @rpath sibling is mapped by the fixture's dlopen")
        #expect(resolvedBareImageNames.contains("libswiftCore"), "an absolute load path must resolve after bare-name normalization")
        #expect(resolvedBareImageNames.contains("Foundation"))

        let directBareImageNames = Set(directLoadNameBareImageNames(of: root))
        #expect(Set(resolvedBareImageNames).isSubset(of: directBareImageNames), "a direct traversal never follows a dependency's own load commands")
        #expect(Set(closure.unresolvedLoadNames.map(DependencyLoadName.bareImageName(of:))).isDisjoint(with: resolvedBareImageNames))
        #expect(resolvedBareImageNames.count + closure.unresolvedLoadNames.count == directBareImageNames.count, "every direct load name is either resolved or reported, exactly once")
        #expect(!resolvedBareImageNames.contains("SymbolTestsCore"), "the root is never its own dependency")
        #expect(closure.searchPathLoadFailures.isEmpty, "the in-process locator has no search paths to fail")
    }

    /// Transitive resolution extends the direct set without reordering it:
    /// the direct dependencies come first, in load-command order, then the
    /// next level. A lazily indexing consumer relies on that prefix.
    @MainActor
    @Test func inProcessTransitiveClosureExtendsTheDirectPrefixBreadthFirst() throws {
        let root = machOImage
        let direct = DependencyClosure(root: root, traversal: .direct)
        let transitive = DependencyClosure(root: root, traversal: .transitive)

        let directBareImageNames = bareImageNames(of: direct.images)
        let transitiveBareImageNames = bareImageNames(of: transitive.images)
        #expect(Array(transitiveBareImageNames.prefix(directBareImageNames.count)) == directBareImageNames)
        #expect(transitiveBareImageNames.count > directBareImageNames.count, "Foundation alone pulls in images the fixture does not link directly")
        #expect(Set(transitiveBareImageNames).count == transitiveBareImageNames.count, "deduplicated by bare image name")
        #expect(!transitiveBareImageNames.contains("SymbolTestsCore"))
    }

    // MARK: - Offline

    @MainActor
    @Test func offlineClosureResolvesExplicitFilesAndCacheImages() throws {
        guard FullDyldCache.host != nil else {
            print("skipped: no host dyld shared cache")
            return
        }
        let root = machOFile
        let closure = DependencyClosure(
            root: root,
            searchPaths: [.machOFile(path: Self.symbolTestsHelperOnDiskPath), .systemDyldSharedCache],
            traversal: .direct
        )

        #expect(closure.searchPathLoadFailures.isEmpty)
        let helper = try #require(closure.images.first { DependencyLoadName.bareImageName(of: $0.imagePath) == "SymbolTestsHelper" })
        #expect(helper.imagePath == Self.symbolTestsHelperLoadName, "the explicit file is the one the @rpath load name names")
        let swiftCore = try #require(closure.images.first { DependencyLoadName.bareImageName(of: $0.imagePath) == "libswiftCore" })
        #expect(swiftCore.imagePath == Self.swiftCoreLoadName, "a cache image resolves by its exact install path")
        #expect(!closure.unresolvedLoadNames.contains(Self.symbolTestsHelperLoadName))
    }

    /// Without the explicit file the `@rpath` sibling is exactly the kind of
    /// dependency the cache cannot answer — it must be reported, not dropped.
    @MainActor
    @Test func offlineClosureReportsWhatTheCacheCannotAnswer() throws {
        guard FullDyldCache.host != nil else {
            print("skipped: no host dyld shared cache")
            return
        }
        let closure = DependencyClosure(root: machOFile, searchPaths: [.systemDyldSharedCache], traversal: .direct)
        #expect(closure.unresolvedLoadNames.contains(Self.symbolTestsHelperLoadName))
        #expect(!bareImageNames(of: closure.images).contains("SymbolTestsHelper"))
    }

    @MainActor
    @Test func offlineClosureWithNoSearchPathsReportsEveryDependency() throws {
        let root = machOFile
        let closure = DependencyClosure(root: root, searchPaths: [], traversal: .transitive)
        #expect(closure.images.isEmpty)
        #expect(closure.unresolvedLoadNames.map(DependencyLoadName.bareImageName(of:)) == directLoadNameBareImageNames(of: root), "reported in load-command order, deduplicated by bare name")
    }

    @MainActor
    @Test func unopenableSearchPathIsRecordedRatherThanThrown() throws {
        let missingPath = "/nonexistent/MachODependenciesTests/Missing.framework/Missing"
        let closure = DependencyClosure(root: machOFile, searchPaths: [.machOFile(path: missingPath)], traversal: .direct)
        #expect(closure.searchPathLoadFailures.count == 1)
        #expect(closure.searchPathLoadFailures.first?.searchPath == .machOFile(path: missingPath))
        #expect(closure.images.isEmpty)
    }

    // MARK: - Locator seam

    /// A locator conforming to `DependencyLocating` receives every load name
    /// in its raw load-command spelling, exactly once per bare name.
    private final class RecordingLocator: DependencyLocating {
        private(set) var receivedLoadNames: [String] = []
        private let imagesByBareImageName: [String: MachOFile]

        init(imagesByBareImageName: [String: MachOFile]) {
            self.imagesByBareImageName = imagesByBareImageName
        }

        func locate(loadName: String) -> MachOFile? {
            receivedLoadNames.append(loadName)
            return imagesByBareImageName[DependencyLoadName.bareImageName(of: loadName)]
        }
    }

    /// One image reached under two spellings is collected once. The file
    /// locator registers an explicit file under its on-disk path, its install
    /// name and its bare name, so a root that links the same binary under two
    /// load names would otherwise get it twice: bare-name deduplication sees
    /// two names, but the resolved image is one, and `ImageUniverse` would
    /// index it twice. Identity is `MachORepresentableWithCache.identifier`
    /// (`LC_UUID`-keyed for a file), so two `MachOFile` values over the same
    /// binary compare equal.
    @MainActor
    @Test func sameImageReachedUnderTwoLoadNamesIsCollectedOnce() throws {
        let root = machOFile
        let helperFile = try #require(File.loadFromFile(url: URL(fileURLWithPath: Self.symbolTestsHelperOnDiskPath)).machOFiles.first)
        // Two of the root's direct load names, both answered by the same file.
        let locator = RecordingLocator(imagesByBareImageName: ["SymbolTestsHelper": helperFile, "libswiftCore": helperFile])

        let closure = DependencyClosure(root: root, traversal: .direct, locator: locator)

        #expect(closure.images.count == 1, "the same image must not be collected under a second load name")
        #expect(closure.images.first?.imagePath == helperFile.imagePath)
        #expect(!closure.unresolvedLoadNames.contains(Self.symbolTestsHelperLoadName))
        #expect(!closure.unresolvedLoadNames.contains(Self.swiftCoreLoadName), "a load name answered by an already-collected image is resolved, not reported")
    }

    @MainActor
    @Test func customLocatorReceivesRawLoadNamesAndSuppliesTheImages() throws {
        let root = machOFile
        let helperFile = try #require(File.loadFromFile(url: URL(fileURLWithPath: Self.symbolTestsHelperOnDiskPath)).machOFiles.first)
        let locator = RecordingLocator(imagesByBareImageName: ["SymbolTestsHelper": helperFile])

        let closure = DependencyClosure(root: root, traversal: .direct, locator: locator)

        #expect(locator.receivedLoadNames.contains(Self.symbolTestsHelperLoadName), "the locator sees the @rpath spelling, not a pre-normalized name")
        #expect(locator.receivedLoadNames == directLoadNameBareImageNames(of: root).map { bareImageName in root.dependencies.first { DependencyLoadName.bareImageName(of: $0.dylib.name) == bareImageName }!.dylib.name })
        #expect(closure.images.count == 1)
        #expect(closure.images.first?.imagePath == helperFile.imagePath)
        #expect(closure.unresolvedLoadNames.count == locator.receivedLoadNames.count - 1)
    }
}
