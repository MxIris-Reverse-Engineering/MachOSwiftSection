import Testing
import SwiftSectionFixtureSupport
import SwiftSectionTestingSupport

/// `ExclusiveImageAccess` excludes only suites that spell the same key. A
/// suite may name a SymbolTests fixture by its file and another by its image;
/// both must reach the same key, or the two run at once while each believes
/// it holds the image alone. (The trait itself is tested in
/// MachOKitExtensions.)
@Suite
struct ExclusiveImageAccessKeyTests {
    @Test("A SymbolTests fixture keys the exclusion the same by its file and by its image", arguments: [
        (MachOFileName.SymbolTests, MachOImageName.SymbolTests),
        (.SymbolTestsCore, .SymbolTestsCore),
    ])
    func fileAndImageOfOneFixtureShareTheKey(fileName: MachOFileName, imageName: MachOImageName) {
        #expect(fileName.exclusiveAccessKey == imageName.exclusiveAccessKey)
        #expect(imageName.exclusiveAccessKey == imageName.name)
    }

    @Test("Different SymbolTests fixtures key the exclusion differently")
    func differentFixturesHaveDifferentKeys() {
        let keys: Set = [
            MachOFileName.SymbolTests.exclusiveAccessKey,
            MachOFileName.SymbolTestsCore.exclusiveAccessKey,
            MachOFileName.SymbolTestsHelper.exclusiveAccessKey,
        ]
        #expect(keys.count == 3)
    }
}
