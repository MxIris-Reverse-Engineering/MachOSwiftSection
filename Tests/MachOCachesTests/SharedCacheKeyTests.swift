import Foundation
import Testing
import MachOKitExtensions
@_spi(Internals) import MachOCaches

/// `SharedCacheKey` hashes a `uuidFile` identifier on its UUID alone, a
/// `dyldCacheImage` identifier on its two UUIDs and an `image` identifier on
/// its base address alone; the path still decides equality. These pin both
/// halves, since a key that hashed differently for equal identifiers would
/// miss its own entry, and one that compared equal across paths — or across
/// caches — would hand one binary another binary's index.
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

    @Test func dyldCacheImageKeysHashOnTheTwoUUIDs() {
        let cacheUUID = UUID()
        let first = SharedCacheKey(identifier: .dyldCacheImage(path: "/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI", uuid: uuid, cacheUUID: cacheUUID))
        let second = SharedCacheKey(identifier: .dyldCacheImage(path: "/System/iOSSupport/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI", uuid: uuid, cacheUUID: cacheUUID))

        #expect(first.hashValue == second.hashValue, "the path is not part of the hash")
        #expect(first != second, "the path still takes part in equality")
    }

    /// The macOS 13.5 and 13.6 caches carry the same SwiftUI build, `LC_UUID`
    /// included, at different addresses. Sharing an entry between the two
    /// copies sent the one read second to the first one's class objects.
    @Test func oneBuildInTwoCachesMakesDifferentKeys() {
        let path = "/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI"
        let first = SharedCacheKey(identifier: .dyldCacheImage(path: path, uuid: uuid, cacheUUID: UUID()))
        let second = SharedCacheKey(identifier: .dyldCacheImage(path: path, uuid: uuid, cacheUUID: UUID()))

        #expect(first != second)
        #expect(SharedCacheKey(identifier: .dyldCacheImage(path: path, uuid: uuid, cacheUUID: UUID())) != SharedCacheKey(identifier: .uuidFile(path: path, uuid: uuid)), "an image read from a cache is never the extracted file of the same build")
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
