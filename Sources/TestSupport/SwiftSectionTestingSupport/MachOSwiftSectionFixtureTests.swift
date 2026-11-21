import Foundation
import MachOTestingSupport
import SwiftSectionFixtureSupport

/// A suite that reads the SymbolTestsCore fixture both from its file and as
/// this process loaded it.
///
/// The readers, the reading contexts and `acrossAllReaders` /
/// `acrossAllContexts` / `usingInProcessOnly` come from MachOKitExtensions'
/// `MachOFixtureTests`; this class says which fixture to read and turns a
/// fixture that cannot be read into a `FixtureLoadError` that tells how to
/// rebuild it.
package class MachOSwiftSectionFixtureTests: MachOFixtureTests {
    package class var fixtureFileName: MachOFileName { .SymbolTestsCore }
    package class var fixtureImageName: MachOImageName { .SymbolTestsCore }

    /// The file of ``fixtureFileName``, found in this process by
    /// ``fixtureImageName`` after loading it.
    override package class var fixture: MachOFixture {
        MachOFixture(fileURL: fixtureFileName.url, imageName: fixtureImageName.name, loadsIntoProcess: true)
    }

    package override init() async throws {
        do {
            try await super.init()
        } catch MachOFixtureError.fileMissing(let path) {
            throw FixtureLoadError.fixtureFileMissing(path: path)
        } catch MachOFixtureError.imageNotLoaded(_, let dynamicLoaderError) {
            throw FixtureLoadError.imageNotFoundAfterDlopen(path: Self.fixtureFileName.path, dlerror: dynamicLoaderError)
        }
    }
}
