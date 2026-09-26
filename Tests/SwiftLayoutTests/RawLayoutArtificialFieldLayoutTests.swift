import Foundation
import Testing
import MachOKit
import MachOFoundation
import Demangling
@testable import MachOSwiftSection
@testable import SwiftLayout

/// Where the archived-cache-gated suite below finds its cache. A separate
/// type on purpose: a `@Suite(.enabled(if:))` condition that reads a static
/// of the suite it decorates is a circular macro reference.
enum ArchivedMacOS27CacheFixtures {
    /// macOS 27.0, arm64e — the first OS whose frameworks a Swift 6.4
    /// compiler built, so its Synchronization module carries the artificial
    /// `_rawLayout` field records.
    static let cachePath = "/Volumes/DyldSharedCaches/macOS/27.0/dyld_shared_cache_arm64e"
    static let synchronizationInstallPath = "/usr/lib/swift/libswiftSynchronization.dylib"
    static var hasCache: Bool { FileManager.default.fileExists(atPath: cachePath) }

    static func synchronizationImage() throws -> MachOFile {
        let cache = try DyldCache(url: URL(fileURLWithPath: cachePath))
        return try #require(cache.machOFile(by: .path(synchronizationInstallPath)), "the archived cache has no \(synchronizationInstallPath)")
    }
}

/// A `@_rawLayout(like: T)` struct has no stored properties; since Swift 6.4
/// its field descriptor carries one **artificial** record naming `T`, so the
/// engine can size it. The expected numbers are the runtime's
/// (`MemoryLayout` measured on macOS 26.6): `_Cell<UnsafePointer<Int>>` is 8
/// bytes and its Optional is 9, because raw storage exposes none of the like
/// type's extra inhabitants.
@Suite(.enabled(if: ArchivedMacOS27CacheFixtures.hasCache))
struct RawLayoutArtificialFieldLayoutTests {
    private func resolveLayout(ofMangledType mangledTypeName: String) throws -> StaticTypeLayout {
        let image = try ArchivedMacOS27CacheFixtures.synchronizationImage()
        let universe = try ImageUniverse.singleImage(image)
        let resolver = StaticTypeLayoutResolver(imageUniverse: universe)
        let typeNode = try demangleAsNode(mangledTypeName, isType: true)
        return try resolver.layout(forTypeNode: typeNode, in: universe.rootImage)
    }

    /// `_MutexHandle { let value: _Cell<os_unfair_lock_s> }`: the like type
    /// is the 4-byte lock, so the handle is 4 bytes with no extra inhabitants.
    @Test func rawLayoutStorageTakesTheLikeTypeSizeButNoExtraInhabitants() throws {
        let layout = try resolveLayout(ofMangledType: "15Synchronization12_MutexHandleV")
        #expect(layout.size == 4)
        #expect(layout.stride == 4)
        #expect(layout.alignmentMask == 3)
        #expect(layout.extraInhabitantCount == 0)
    }

    /// The raw-layout flags: never bitwise-borrowable, always
    /// addressable-for-dependencies (SIL `TypeLowering` for `RawLayoutAttr`).
    @Test func rawLayoutStorageIsNotBorrowableAndIsAddressable() throws {
        let layout = try resolveLayout(ofMangledType: "15Synchronization5_CellVySPySiGG")
        #expect(layout.size == 8)
        #expect(layout.extraInhabitantCount == 0)
        #expect(layout.isBitwiseBorrowable == false)
        #expect(layout.isAddressableForDependencies == true)
    }

    /// `Optional<_Cell<UnsafePointer<Int>>>` needs a tag byte: the pointer's
    /// null is not available through the raw storage. Runtime truth 9 / 16.
    @Test func optionalOfRawLayoutStorageGrowsATagByte() throws {
        let layout = try resolveLayout(ofMangledType: "15Synchronization5_CellVySPySiGGSg")
        #expect(layout.size == 9)
        #expect(layout.stride == 16)
        #expect(layout.extraInhabitantCount == 0)
    }

    /// A borrow of raw-layout storage takes the pointer representation (the
    /// referent is not bitwise-borrowable), whatever its size.
    @Test func borrowOfRawLayoutStorageIsAPointer() throws {
        let layout = try resolveLayout(ofMangledType: "15Synchronization5_CellVySPySiGGBW")
        #expect(layout.size == 8)
        #expect(layout.extraInhabitantCount == 1)
    }
}
