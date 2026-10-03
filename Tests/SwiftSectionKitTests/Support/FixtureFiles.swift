import Foundation

/// Paths the request tests hand to `MachOSource` / `SnapshotSource`, which take
/// paths rather than loaded images.
enum FixtureFiles {
    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Support
        .deletingLastPathComponent() // SwiftSectionKitTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // package root

    /// The SymbolTestsCore fixture framework binary (thin arm64). A gitignored
    /// per-machine build product; see FixtureTestingAndContinuousIntegration.md.
    static let symbolTestsCore = packageRoot
        .appendingPathComponent("Tests/Projects/SymbolTests/DerivedData/SymbolTests/Build/Products/Release/SymbolTestsCore.framework/Versions/A/SymbolTestsCore")
        .path

    /// A fresh directory for one test's files.
    static func makeTemporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftSectionKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    /// A fat file whose one slice is the thin arm64 binary at `thinPath`.
    ///
    /// Built by hand rather than taken from the host: whether a system binary
    /// is fat, and with which slices, changes between OS releases.
    static func makeSingleSliceFatFile(wrapping thinPath: String, in directoryURL: URL) throws -> String {
        let thinData = try Data(contentsOf: URL(fileURLWithPath: thinPath))
        let sliceAlignmentPower: UInt32 = 14
        let sliceOffset: UInt32 = 1 << sliceAlignmentPower
        var fatData = Data()
        func appendBigEndian(_ value: UInt32) {
            withUnsafeBytes(of: value.bigEndian) { fatData.append(contentsOf: $0) }
        }
        appendBigEndian(0xCAFE_BABE) // FAT_MAGIC
        appendBigEndian(1) // nfat_arch
        appendBigEndian(0x0100_000C) // CPU_TYPE_ARM64
        appendBigEndian(0) // CPU_SUBTYPE_ARM64_ALL
        appendBigEndian(sliceOffset)
        appendBigEndian(UInt32(thinData.count))
        appendBigEndian(sliceAlignmentPower)
        fatData.append(Data(count: Int(sliceOffset) - fatData.count))
        fatData.append(thinData)
        let fatURL = directoryURL.appendingPathComponent("SingleSliceFat")
        try fatData.write(to: fatURL)
        return fatURL.path
    }
}
