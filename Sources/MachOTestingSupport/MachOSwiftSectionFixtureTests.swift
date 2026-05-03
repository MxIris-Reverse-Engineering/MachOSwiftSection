import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOReading
import MachOResolving
import MachOFixtureSupport

@MainActor
package class MachOSwiftSectionFixtureTests: Sendable {
    package let machOFile: MachOFile
    package let machOImage: MachOImage

    package let fileContext: MachOContext<MachOFile>
    package let imageContext: MachOContext<MachOImage>
    package let inProcessContext: InProcessContext

    package class var fixtureFileName: MachOFileName { .SymbolTestsCore }
    package class var fixtureImageName: MachOImageName { .SymbolTestsCore }
    package class var preferredArchitecture: CPUType { .arm64 }

    package init() async throws {
        // 1) Load MachO from disk.
        let file: File
        do {
            file = try loadFromFile(named: Self.fixtureFileName)
        } catch {
            // If the file doesn't exist on disk, surface a fixture-specific
            // error with rebuild instructions. Otherwise propagate the original
            // error so unrelated load failures aren't masked.
            let resolvedPath = Self.resolveFixturePath(Self.fixtureFileName.rawValue)
            if !FileManager.default.fileExists(atPath: resolvedPath) {
                throw FixtureLoadError.fixtureFileMissing(path: resolvedPath)
            }
            throw error
        }
        switch file {
        case .fat(let fatFile):
            self.machOFile = try required(
                fatFile.machOFiles().first(where: { $0.header.cpuType == Self.preferredArchitecture })
                    ?? fatFile.machOFiles().first
            )
        case .machO(let machO):
            self.machOFile = machO
        @unknown default:
            fatalError()
        }

        // 2) Ensure fixture is dlopen'd into the test process so MachOImage(name:) succeeds.
        // `MachOImage(name:)` matches by the bare module name (last path component
        // with extension stripped), not by the full path. Derive that from the
        // fixtureImageName rawValue, which is a relative filesystem path.
        try Self.ensureFixtureLoaded()
        let imageLookupName = Self.imageLookupName(from: Self.fixtureImageName.rawValue)
        guard let image = MachOImage(name: imageLookupName) else {
            throw FixtureLoadError.imageNotFoundAfterDlopen(
                path: Self.fixtureImageName.rawValue,
                dlerror: Self.lastDlerror()
            )
        }
        self.machOImage = image

        // 3) Three ReadingContext instances over the same fixture.
        self.fileContext = MachOContext(machOFile)
        self.imageContext = MachOContext(machOImage)
        self.inProcessContext = InProcessContext()
    }

    private static let dlopenOnce: Void = {
        let absolute = resolveFixturePath(MachOImageName.SymbolTestsCore.rawValue)
        _ = absolute.withCString { dlopen($0, RTLD_LAZY) }
    }()

    private static func ensureFixtureLoaded() throws {
        _ = dlopenOnce
    }

    /// Resolve a relative MachOImageName path (rooted at the package-relative `../../Tests/...`
    /// convention) to an absolute filesystem path. Uses the same anchor strategy as
    /// `loadFromFile` for parity: relative paths resolve against the directory containing
    /// this source file (i.e. `Sources/MachOTestingSupport/`).
    private static func resolveFixturePath(_ relativePath: String) -> String {
        if relativePath.hasPrefix("/") { return relativePath }
        let url = URL(fileURLWithPath: relativePath, relativeTo: URL(fileURLWithPath: #filePath))
        return url.standardizedFileURL.path
    }

    private static func lastDlerror() -> String? {
        guard let cString = dlerror() else { return nil }
        return String(cString: cString)
    }

    /// Derive the bare module name `MachOImage(name:)` expects (last path component
    /// with extension stripped) from a path-form `MachOImageName.rawValue`.
    private static func imageLookupName(from rawValue: String) -> String {
        let lastComponent = rawValue.components(separatedBy: "/").last ?? rawValue
        return lastComponent.components(separatedBy: ".").first ?? lastComponent
    }
}

extension MachOSwiftSectionFixtureTests {
    /// Run `body` against each (label, reader) pair, asserting all results equal the first.
    /// Returns the unique value. Fails fast with the label of the first mismatching reader.
    package func acrossAllReaders<T: Equatable>(
        file fileWork: () throws -> T,
        image imageWork: () throws -> T,
        inProcess inProcessWork: (() throws -> T)? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> T {
        let fromFile = try fileWork()
        let fromImage = try imageWork()
        #expect(fromFile == fromImage, "MachOFile vs MachOImage diverged", sourceLocation: sourceLocation)
        if let inProcessWork {
            let fromInProcess = try inProcessWork()
            #expect(fromFile == fromInProcess, "MachOFile vs InProcess diverged", sourceLocation: sourceLocation)
        }
        return fromFile
    }

    /// Run `body` against each ReadingContext (file/image/inProcess), asserting all equal.
    package func acrossAllContexts<T: Equatable>(
        file fileWork: () throws -> T,
        image imageWork: () throws -> T,
        inProcess inProcessWork: (() throws -> T)? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> T {
        let fromFileCtx = try fileWork()
        let fromImageCtx = try imageWork()
        #expect(fromFileCtx == fromImageCtx, "fileContext vs imageContext diverged", sourceLocation: sourceLocation)
        if let inProcessWork {
            let fromInProcessCtx = try inProcessWork()
            #expect(fromFileCtx == fromInProcessCtx, "fileContext vs inProcessContext diverged", sourceLocation: sourceLocation)
        }
        return fromFileCtx
    }
}
