import Foundation
import Testing
import MachOKit
import MachOObjCSection
@testable import SwiftInspection

private enum TwinSwiftUICaches {
    static let swiftUIPath = "/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI"
    static let joinedViewsRuntimeName = "_TtCV7SwiftUI12_ViewList_ID11JoinedViews"

    static func url(of version: String) -> URL {
        URL(fileURLWithPath: "/Volumes/DyldSharedCaches/macOS/\(version)/dyld_shared_cache_arm64e")
    }

    static var areAvailable: Bool {
        ["13.5", "13.6"].allSatisfy { FileManager.default.fileExists(atPath: url(of: $0).path) }
    }

    /// The offset of the class object the image's own class list names
    /// `runtimeName` — the answer the index must give for this image.
    static func ownClassObjectOffset(named runtimeName: String, in machOFile: MachOFile) -> Int? {
        machOFile.objc.classes64?.first { $0.classROData(in: machOFile)?.name(in: machOFile) == runtimeName }?.offset
    }
}

/// The macOS 13.5 and 13.6 dyld caches carry the same SwiftUI build — the same
/// `LC_UUID` — at different addresses. Per-image caches keyed by the image
/// alone handed the copy read second the first one's class objects: reading
/// 13.6's `JoinedViews` in the 13.5 cache landed on a slot holding `0xa9`, and
/// decoding that as a pointer trapped in MachOKit. An evolution interface over
/// every archived macOS cache crashed this way.
@Suite(.enabled(if: TwinSwiftUICaches.areAvailable, "needs the archived macOS 13.5 and 13.6 dyld caches"))
struct DyldCacheTwinImageTests {
    @Test func eachCacheIndexesItsOwnClassObjects() throws {
        let newerCache = try DyldCache(url: TwinSwiftUICaches.url(of: "13.6"))
        let olderCache = try DyldCache(url: TwinSwiftUICaches.url(of: "13.5"))
        let newerImage = try #require(newerCache.machOFile(by: .path(TwinSwiftUICaches.swiftUIPath)))
        let olderImage = try #require(olderCache.machOFile(by: .path(TwinSwiftUICaches.swiftUIPath)))
        let runtimeName = TwinSwiftUICaches.joinedViewsRuntimeName
        let newerOffset = try #require(TwinSwiftUICaches.ownClassObjectOffset(named: runtimeName, in: newerImage))
        let olderOffset = try #require(TwinSwiftUICaches.ownClassObjectOffset(named: runtimeName, in: olderImage))
        try #require(newerOffset != olderOffset, "the premise: the two caches place the class differently")

        // The newer cache first, the order the evolution's concurrent
        // preparation happened to take.
        _ = ObjCClassMethodIndex.shared.hierarchy(forRuntimeName: runtimeName, in: newerImage)
        #expect(ObjCClassMethodIndex.shared.storage(in: olderImage)?.classObjectsByRuntimeName[runtimeName]?.offset == olderOffset)
        #expect(ObjCClassMethodIndex.shared.storage(in: newerImage)?.classObjectsByRuntimeName[runtimeName]?.offset == newerOffset)
        _ = ObjCClassMethodIndex.shared.hierarchy(forRuntimeName: runtimeName, in: olderImage)

        withExtendedLifetime((newerCache, olderCache)) {}
    }

    /// The slot the newer cache's class data offset lands on in the older
    /// cache: a small integer, which slide info decodes as a pointer below the
    /// shared region. MachOKit subtracted the region start from it and trapped.
    @Test func aSlotHoldingNoPointerResolvesToNoRebase() throws {
        let url = TwinSwiftUICaches.url(of: "13.5")
        let slotOffset: UInt64 = 0x59BE_A800
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }
        try fileHandle.seek(toOffset: slotOffset)
        let slotBytes = try #require(try fileHandle.read(upToCount: 8))
        let slotValue = slotBytes.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
        try #require(slotValue == 0xa9, "the premise: the slot holds the integer, not a pointer")

        #expect(try DyldCache(url: url).resolveOptionalRebase(at: slotOffset) == nil)
    }
}
