import MachOKitExtensions
import Testing
import Foundation
import MachOKit

/// Regression coverage for deciding whether an in-process image belongs to the
/// dyld shared cache.
///
/// `MachOImage.cache` used to call an image a cache image whenever its mach
/// header sat at or above the cache's unslid `sharedRegionStart`
/// (`0x180000000` on arm64). An image outside the cache usually loads below
/// that, but not always: in a full `swift test` run the dlopen'ed
/// `SymbolTestsCore` fixture landed at `0x70627cc000`, far past the end of the
/// cache. Taken for a cache image, it reported every address shifted by the
/// cache's slide, and `ProtocolRecordTests`, whose fixture picker derives its
/// read offset from the same answer, read `0x180000000` bytes too low — wrong
/// values in one run, a SIGBUS in another.
///
/// Membership is a property of the image, recorded by the cache builder as the
/// header's `MH_DYLIB_IN_CACHE` flag; where the image happens to be mapped says
/// nothing. The cases below map a copy of this test bundle's own header and
/// load commands past the end of the shared region, so the address is chosen
/// here instead of by wherever dyld found room.
@Suite
struct MachOImageCacheMembershipTests {
    @Test func imageOutsideTheCacheIsNotACacheImageWhereverItIsMapped() throws {
        try withCopyMappedPastTheSharedRegion(of: MachOImage.current()) { relocatedImage in
            #expect(relocatedImage.cache == nil)
        }
    }

    @Test func imageOutsideTheCacheReportsTheSameAddressesWhereverItIsMapped() throws {
        let image = MachOImage.current()
        let memberOffset = 0x4000
        try withCopyMappedPastTheSharedRegion(of: image) { relocatedImage in
            #expect(relocatedImage.address(forOffset: memberOffset) == image.address(forOffset: memberOffset))
        }
    }

    @Test func imageInTheCacheIsACacheImage() throws {
        let image = try #require(MachOImage(name: "libswiftCore"))
        #expect(image.cache != nil)
    }

    /// Maps a copy of `image`'s mach header and load commands at the first free
    /// address past the end of the shared region and hands `body` an image over
    /// the copy. The header and the load commands are all that the membership
    /// answer and `address(forOffset:)` read.
    private func withCopyMappedPastTheSharedRegion(
        of image: MachOImage,
        _ body: (MachOImage) throws -> Void
    ) throws {
        let currentCache = try #require(DyldCacheLoaded.current)
        let sharedRegionEnd = UInt(bitPattern: currentCache.ptr) + UInt(currentCache.mainCacheHeader.sharedRegionSize)
        let byteCount = image.headerSize + Int(image.header.sizeofcmds)
        let mapping = mmap(UnsafeMutableRawPointer(bitPattern: sharedRegionEnd), byteCount, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0)
        let relocatedPointer = try #require(mapping == MAP_FAILED ? nil : mapping)
        defer { munmap(relocatedPointer, byteCount) }
        // The premise: past the cache, and so above `sharedRegionStart`, where
        // the old lower-bound test answered "in the cache".
        try #require(UInt(bitPattern: relocatedPointer) >= sharedRegionEnd)
        relocatedPointer.copyMemory(from: image.ptr, byteCount: byteCount)
        try body(MachOImage(ptr: relocatedPointer.assumingMemoryBound(to: mach_header.self)))
    }
}
