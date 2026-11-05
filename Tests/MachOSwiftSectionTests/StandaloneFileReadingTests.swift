import Foundation
import Testing
import MachOKit
import MachOReading
import MachOFixtureSupport

/// A read of a standalone file — one not read out of a dyld shared cache —
/// comes from the file's own mapping and never goes back to its path.
///
/// Every read asks the file for the sub-cache an offset lies in, which only
/// an image of a cache has. MachOKit's `cache` answered that by opening the
/// file's path as a dyld cache, and for a standalone file it failed and was
/// asked again on the next read: each read mapped and unmapped the whole file,
/// two thirds of the time spent reading the iOS 18.5 simulator's SwiftUI.
///
/// The test opens a copy of the fixture, then puts a dyld cache header at the
/// copy's path. The file's mapping keeps the original bytes, so a read that
/// went back to the path would come from the header instead.
@Suite
struct StandaloneFileReadingTests {
    private static var isHostDyldCacheAvailable: Bool {
        FileManager.default.fileExists(atPath: DyldSharedCachePath.current.rawValue)
    }

    @Test(.enabled(if: isHostDyldCacheAvailable))
    func readsComeFromTheFileEvenAfterItsPathNamesADyldCache() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StandaloneFileReadingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        guard case .machO(let fixture) = try loadFromFile(named: .SymbolTestsCore) else {
            Issue.record("the fixture is expected to be a thin file")
            return
        }
        let copyURL = temporaryDirectory.appendingPathComponent("SymbolTestsCore")
        try FileManager.default.copyItem(at: fixture.url, to: copyURL)
        guard case .machO(let machOFile) = try MachOKit.loadFromFile(url: copyURL) else {
            Issue.record("the copy is expected to be a thin file")
            return
        }
        let magic: UInt32 = try machOFile.context.readElement(at: 0)
        let headerBytes: [UInt8] = try machOFile.context.readElements(at: 0, numberOfElements: 64)
        #expect(!machOFile.isLoadedFromDyldCache)

        // Replace, not overwrite: the mapping `machOFile` reads keeps the
        // fixture's bytes.
        let cacheHeaderBytes = try Self.hostCacheHeaderBytes()
        try cacheHeaderBytes.write(to: copyURL, options: .atomic)

        #expect(try machOFile.context.readElement(at: 0) as UInt32 == magic)
        #expect(try machOFile.context.readElements(at: 0, numberOfElements: 64) as [UInt8] == headerBytes)
    }

    /// The first bytes of the host's dyld cache: enough for MachOKit to accept
    /// a file as a cache.
    private static func hostCacheHeaderBytes() throws -> Data {
        let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: DyldSharedCachePath.current.rawValue))
        defer { try? fileHandle.close() }
        return try #require(try fileHandle.read(upToCount: 0x10000))
    }
}
