import Foundation
@_spi(Support) import MachOKit
import Testing
@testable import MachODependencies
import MachOFixtureSupport

/// Every `FileDependencyLocator` that names one Mach-O file as an explicit
/// search path reads one opening of it, for as long as anything still holds
/// that opening.
///
/// A locator reads every explicit file it is given when it is built, and each
/// consumer of a dependency closure builds one per root: RuntimeViewer reading
/// a bundle names every Mach-O file of the bundle, so each file was opened
/// again for every image of the bundle and every consumer.
///
/// The tests read a copy of the fixture's `SymbolTestsHelper`, so no other
/// suite can be holding the same file.
@Suite
struct SharedMachOFileOpeningTests {
    /// More locators than a service starts with descriptors: one opening of
    /// the file per locator exceeds the limit, one shared opening does not.
    private static let locatorCount = 300

    /// The descriptor limit launchd starts an XPC service with.
    private static let serviceDescriptorLimit: rlim_t = 256

    fileprivate static let fixturePath: String = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Tests/Projects/SymbolTests/DerivedData/SymbolTests/Build/Products/Release/SymbolTestsHelper.framework/Versions/A/SymbolTestsHelper")
        .path

    private static var isFixtureAvailable: Bool {
        FileManager.default.fileExists(atPath: fixturePath)
    }

    @Test(.enabled(if: isFixtureAvailable))
    func locatorsNamingOneFileShareOneOpening() throws {
        let copy = try FixtureCopy()
        defer { copy.remove() }
        let firstImage = try #require(FileDependencyLocator(searchPaths: [.machOFile(path: copy.path)]).locate(loadName: copy.path))
        let secondImage = try #require(FileDependencyLocator(searchPaths: [.machOFile(path: copy.path)]).locate(loadName: copy.path))

        #expect(secondImage === firstImage)
    }

    /// Shared, but not kept: once nothing holds an opening it closes. In a
    /// child process, so nothing else in the process can be holding it.
    @Test(.enabled(if: isFixtureAvailable))
    func anOpeningNothingHoldsIsReleased() async {
        await #expect(processExitsWith: .success) {
            exit(SharedMachOFileOpeningTests.openingIsReleasedOnceNothingHoldsIt() ? EXIT_SUCCESS : EXIT_FAILURE)
        }
    }

    /// Many roots' locators naming one file, all alive at once, under the
    /// descriptor limit a service starts with. Soft and hard limit both: the
    /// first use of `CFSocket` raises the soft limit by 2,304 within the hard
    /// one.
    @Test(.enabled(if: isFixtureAvailable))
    func locatorsOfManyRootsStayWithinAServiceDescriptorLimit() async {
        await #expect(processExitsWith: .success) {
            exit(SharedMachOFileOpeningTests.locatorsLocateUnderTheServiceDescriptorLimit() ? EXIT_SUCCESS : EXIT_FAILURE)
        }
    }

    // MARK: - Exit test bodies

    static func openingIsReleasedOnceNothingHoldsIt() -> Bool {
        guard let copy = try? FixtureCopy() else { return false }
        defer { copy.remove() }
        weak var openedFile: MachOFile?
        autoreleasepool {
            openedFile = FileDependencyLocator(searchPaths: [.machOFile(path: copy.path)]).locate(loadName: copy.path)
        }
        guard openedFile == nil else { return false }
        // Opened again, it is a new instance that works.
        return FileDependencyLocator(searchPaths: [.machOFile(path: copy.path)]).locate(loadName: copy.path) != nil
    }

    static func locatorsLocateUnderTheServiceDescriptorLimit() -> Bool {
        guard let copy = try? FixtureCopy() else { return false }
        defer { copy.remove() }
        var limit = rlimit(rlim_cur: serviceDescriptorLimit, rlim_max: serviceDescriptorLimit)
        guard setrlimit(RLIMIT_NOFILE, &limit) == 0 else { return false }
        var heldLocators: [FileDependencyLocator] = []
        for _ in 0 ..< locatorCount {
            let locator = FileDependencyLocator(searchPaths: [.machOFile(path: copy.path)])
            guard locator.loadFailures.isEmpty, locator.locate(loadName: copy.path) != nil else {
                return false
            }
            heldLocators.append(locator)
        }
        return heldLocators.count == locatorCount
    }
}

/// The fixture's `SymbolTestsHelper` copied into a directory of its own.
private struct FixtureCopy {
    let directory: URL
    let path: String

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedMachOFileOpeningTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let copyURL = directory.appendingPathComponent("SymbolTestsHelper")
        try FileManager.default.copyItem(atPath: SharedMachOFileOpeningTests.fixturePath, toPath: copyURL.path)
        path = copyURL.path
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

