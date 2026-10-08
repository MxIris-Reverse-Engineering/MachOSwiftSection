import Foundation
import Testing
import MachOKit
import MachOFoundation
import Demangling
@testable import MachOSwiftSection
@testable import SwiftLayout
import MachOFixtureSupport

/// Where the archived-cache-gated suite below finds its cache. A separate
/// type on purpose: a `@Suite(.enabled(if:))` condition that reads a static
/// of the suite it decorates is a circular macro reference.
enum ArchivedMacOS15LayoutFixtures {
    static let cachePath = DyldSharedCachePath.macOS_15_5
    static var hasCache: Bool { FileManager.default.fileExists(atPath: cachePath.rawValue) }

    static func swiftUICore() throws -> MachOFile {
        let cache = try FullDyldCache(path: cachePath)
        return try #require(
            cache.machOFile(by: .path("/System/Library/Frameworks/SwiftUICore.framework/Versions/A/SwiftUICore")),
            "the macOS 15.5 cache has no SwiftUICore"
        )
    }
}

/// `Foundation.URL` is resilient, so SwiftUICore's `LinkDestination.Configuration`
/// takes its `url` field's size from whichever Foundation the closure finds.
/// In macOS 15.5 that is Foundation's own field records: `_url: NSURL`,
/// `_parseInfo: URLParseInfo?` and `_baseParseInfo: URLParseInfo?`, 24 bytes.
/// macOS 26 rebuilt `URL` around a single `any _URLProtocol & AnyObject`, 16
/// bytes, and that is what an archived cache's image read when its closure
/// fell through to the host's cache.
@Suite(.enabled(if: ArchivedMacOS15LayoutFixtures.hasCache))
struct CacheRootDependencyLayoutTests {
    @Test("A cache image lays out another module's type against its own cache")
    func resilientTypeFromAnotherModuleTakesTheRootCachesLayout() throws {
        let root = try ArchivedMacOS15LayoutFixtures.swiftUICore()
        let universe = try ImageUniverse.dependencyClosure(root: root)
        let resolver = StaticTypeLayoutResolver(imageUniverse: universe)
        let urlNode = try demangleAsNode("10Foundation3URLV", isType: true)
        let urlLayout = try resolver.layout(forTypeNode: urlNode, in: universe.rootImage)
        #expect(urlLayout.size == 24)
    }
}
