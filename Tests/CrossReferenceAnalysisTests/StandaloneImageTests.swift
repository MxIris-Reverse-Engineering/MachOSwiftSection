import Foundation
import Testing
import MachOKit
@testable import CrossReferenceAnalysis

/// An image outside the shared cache — a third-party app's own binary, here
/// the SymbolTestsCore fixture — calls other images through its own
/// `__stubs` / `__auth_stubs`, whose GOT slots dyld bound when it loaded the
/// image.
@Suite(.enabled(if: SharedAnalyzer.analyzer != nil, "needs an arm64 process with a dyld shared cache"))
struct StandaloneImageTests {
    private static var fixturePath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/Projects/SymbolTests/DerivedData/SymbolTests/Build/Products/Release/SymbolTestsCore.framework/Versions/A/SymbolTestsCore")
            .path
    }

    @Test func callsThroughTheImagesOwnStubsReachTheirTargets() throws {
        // A fresh worktree has no fixture: build it, or link the main
        // checkout's DerivedData (AGENTS.md, "a snapshot or baseline test just went red").
        _ = try #require(dlopen(Self.fixturePath, RTLD_NOW), "cannot load the SymbolTestsCore fixture at \(Self.fixturePath)")
        // An analyzer is a snapshot; this one is made after the fixture loaded.
        let analyzer = try #require(CrossReferenceAnalyzer())
        let fixture = try #require(analyzer.imagePaths.firstIndex { $0.hasSuffix("SymbolTestsCore.framework/Versions/A/SymbolTestsCore") })
        #expect(!analyzer.images[fixture].header.isInDyldCache)

        let swiftCore = try #require(analyzer.imagePaths.firstIndex { $0.hasSuffix("/libswiftCore.dylib") })
        let table = analyzer.referenceTable(ofImageAt: fixture)
        let intoSwiftCore = table.references.filter { reference in
            if case .function(let location) = reference.target { location.imageIndex == swiftCore } else { false }
        }
        let intoItself = table.references.filter { reference in
            if case .function(let location) = reference.target { location.imageIndex == fixture } else { false }
        }
        let stuckAtAName = table.references.filter { reference in
            if case .importedSymbol = reference.target { true } else { false }
        }
        #expect(!intoSwiftCore.isEmpty)
        #expect(!intoItself.isEmpty)
        #expect(stuckAtAName.isEmpty, "stubs whose slot was not followed: \(Set(stuckAtAName.map { "\($0.target)" }).sorted().prefix(5))")
        let someCallIsAHelper = table.references.contains { $0.isRuntimeHelperCall }
        #expect(someCallIsAHelper)
    }

    /// An image outside the cache goes by where dyld loaded it: a framework's
    /// install name is `@rpath/…`, which names no file, and a host that knows
    /// the image by its path has to find it by that path.
    @Test func aFrameworkOutsideTheCacheGoesByItsLoadedPath() throws {
        _ = try #require(dlopen(Self.fixturePath, RTLD_NOW), "cannot load the SymbolTestsCore fixture at \(Self.fixturePath)")
        let analyzer = try #require(CrossReferenceAnalyzer())
        let fixture = try #require(analyzer.imagePaths.firstIndex { $0.hasSuffix("SymbolTestsCore.framework/Versions/A/SymbolTestsCore") })
        let path = analyzer.imagePaths[fixture]
        #expect(path.hasPrefix("/"), "\(path)")
        #expect(URL(fileURLWithPath: path).resolvingSymlinksInPath() == URL(fileURLWithPath: Self.fixturePath).resolvingSymlinksInPath())
        #expect(analyzer.imageIndex(forPath: path) == fixture)
        // The install name still finds it: load commands link by it.
        #expect(analyzer.imageIndex(forPath: "@rpath/SymbolTestsCore.framework/Versions/A/SymbolTestsCore") == fixture)
    }

    /// The bundle the tests run in has no install name at all.
    @Test func aBundleGoesByItsLoadedPath() throws {
        let analyzer = try #require(CrossReferenceAnalyzer())
        let testBundle = try #require(analyzer.images.firstIndex { $0.ptr == #dsohandle }, "the test bundle is not among the images")
        #expect(analyzer.images[testBundle].header.fileType == .bundle)
        var information = Dl_info()
        #expect(dladdr(#dsohandle, &information) != 0)
        let loadedPath = String(cString: try #require(information.dli_fname))
        #expect(analyzer.imagePaths[testBundle] == loadedPath)
        #expect(analyzer.imageIndex(forPath: loadedPath) == testBundle)
    }

    /// A bundle linked with `-bundle_loader` binds to the main executable
    /// through no load command, so every bundle counts as linking it.
    @Test func aBundleCountsAsLinkingTheMainExecutable() throws {
        let analyzer = try #require(CrossReferenceAnalyzer())
        let executable = try #require(analyzer.images.firstIndex { $0.header.fileType == .execute })
        let testBundle = try #require(analyzer.images.firstIndex { $0.ptr == #dsohandle })
        #expect(analyzer.imageIndices(linkingImageAt: executable, among: analyzer.images.indices).contains(testBundle))
    }
}
