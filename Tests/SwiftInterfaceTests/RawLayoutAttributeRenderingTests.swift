import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftInterface

/// Where the archived-cache-gated suite below finds its cache (see the
/// SwiftLayout suite of the same shape for why this is a separate type).
enum ArchivedMacOS27InterfaceFixtures {
    static let cachePath = "/Volumes/DyldSharedCaches/macOS/27.0/dyld_shared_cache_arm64e"
    static let synchronizationInstallPath = "/usr/lib/swift/libswiftSynchronization.dylib"
    static var hasCache: Bool { FileManager.default.fileExists(atPath: cachePath) }
}

/// A Swift 6.4 compiler records a `@_rawLayout(like: T)` struct's like type as
/// an artificial `_rawLayout` field. The interface is meant to read like the
/// source, and the source says `@_rawLayout(like: T)` — not a stored property.
@Suite(.enabled(if: ArchivedMacOS27InterfaceFixtures.hasCache))
struct RawLayoutAttributeRenderingTests {
    @Test func theArtificialRecordRendersAsTheAttributeNotAField() async throws {
        let cache = try DyldCache(url: URL(fileURLWithPath: ArchivedMacOS27InterfaceFixtures.cachePath))
        let image = try #require(cache.machOFile(by: .path(ArchivedMacOS27InterfaceFixtures.synchronizationInstallPath)))
        let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: image)
        try await builder.prepare()
        let interface = try await builder.printRoot().string

        // `_Cell<Value: ~Copyable>` is `@_rawLayout(like: Value, movesAsLike)`;
        // the binary records only the like type.
        #expect(interface.contains("@_rawLayout(like: A)\nstruct _Cell<A>"), "\(interface.prefix(4000))")
        // `Atomic<Value>` is `@_rawLayout(like: Value.AtomicRepresentation)`.
        #expect(interface.contains("@_rawLayout(like: A.AtomicRepresentation)\nstruct Atomic<A>"), "\(interface.prefix(4000))")
        #expect(!interface.contains("_rawLayout:"), "the artificial record must not render as a stored property")
    }
}
