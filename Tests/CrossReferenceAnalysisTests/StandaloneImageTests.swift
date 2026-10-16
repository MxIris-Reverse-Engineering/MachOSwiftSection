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
}
