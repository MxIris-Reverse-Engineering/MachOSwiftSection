import Foundation
import Testing
import MachOKitExtensions
@_spi(Internals) import MachOCaches

/// `SharedCacheKey` hashes a `uuidFile` identifier on its UUID alone and an
/// `image` identifier on its base address alone; the path still decides
/// equality. These pin both halves, since a key that hashed differently for
/// equal identifiers would miss its own entry, and one that compared equal
/// across paths would hand one binary another binary's index.
@Suite("SharedCacheKey")
struct SharedCacheKeyTests {
    private let uuid = UUID()

    @Test func uuidFileKeysHashOnTheUUIDAlone() {
        let first = SharedCacheKey(identifier: .uuidFile(path: "/System/Library/Frameworks/SwiftUI.framework/SwiftUI", uuid: uuid))
        let second = SharedCacheKey(identifier: .uuidFile(path: "/tmp/extracted/SwiftUI", uuid: uuid))

        #expect(first.hashValue == second.hashValue, "two paths carrying the same UUID must hash alike: the path is not part of the hash")
        #expect(first != second, "the path still takes part in equality")
    }

    @Test func sameIdentifierMakesEqualKeys() {
        let path = "/System/Library/Frameworks/AppKit.framework/AppKit"
        let first = SharedCacheKey(identifier: .uuidFile(path: path, uuid: uuid))
        let second = SharedCacheKey(identifier: .uuidFile(path: path, uuid: uuid))

        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
    }

    @Test func differentUUIDsMakeDifferentKeys() {
        let path = "/System/Library/Frameworks/AppKit.framework/AppKit"
        let first = SharedCacheKey(identifier: .uuidFile(path: path, uuid: uuid))
        let second = SharedCacheKey(identifier: .uuidFile(path: path, uuid: UUID()))

        #expect(first != second, "the same install path from two builds must not share an entry")
    }

    @Test func imageKeysFollowTheBaseAddress() {
        let storage = UnsafeMutableRawPointer.allocate(byteCount: 16, alignment: 8)
        defer { storage.deallocate() }
        let first = SharedCacheKey(identifier: .image(UnsafeRawPointer(storage)))
        let second = SharedCacheKey(identifier: .image(UnsafeRawPointer(storage)))
        let other = SharedCacheKey(identifier: .image(UnsafeRawPointer(storage + 8)))

        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
        #expect(first != other)
    }

    @Test func pathOnlyIdentifiersStillHashThePath() {
        let first = SharedCacheKey(identifier: .file("/a"))
        let second = SharedCacheKey(identifier: .file("/a"))
        let other = SharedCacheKey(identifier: .file("/b"))

        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
        #expect(first != other)
    }

    @Test func opaqueKeysNeverCollideWithReaderKeys() {
        let opaque = SharedCacheKey(opaque: "/a")
        let reader = SharedCacheKey(identifier: .file("/a"))

        #expect(opaque != reader, "a bare value and a reader identifier spelling the same string are different keys")
        #expect(SharedCacheKey(opaque: "/a") == opaque)
    }
}
