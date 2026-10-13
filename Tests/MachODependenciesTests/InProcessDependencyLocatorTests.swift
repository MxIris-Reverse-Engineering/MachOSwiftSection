#if canImport(Darwin)
import Darwin
#endif
import Foundation
import MachOKit
import Testing
@testable import MachODependencies

/// `InProcessDependencyLocator` answers from one pass over the images dyld
/// has mapped (evolution proposal `faster-lazy-definition-indexing`) and must
/// answer exactly what `MachOImage(name:)`, the per-lookup scan it replaced,
/// answers: the first mapped image carrying the bare name, or nothing.
///
/// Every mapped image's own path is asked for — absolute paths of system
/// frameworks, Swift runtime dylibs and the test bundle alike, including
/// names several mapped images share — together with load-name spellings
/// that must not resolve. The paths are read before the locator is made:
/// other suites map fixtures while this one runs, and an image mapped after
/// the locator was made is, by design, not one it knows.
@Suite
struct InProcessDependencyLocatorTests {
    @Test func answersLikeTheNameLookup() throws {
        var loadNames: Set<String> = [
            "/usr/lib/libNoSuchImage.dylib",
            "@rpath/NoSuchFramework.framework/Versions/A/NoSuchFramework",
            "",
        ]
        #if canImport(Darwin)
        for index in 0 ..< _dyld_image_count() {
            if let pathC = _dyld_get_image_name(index) {
                loadNames.insert(String(cString: pathC))
            }
        }
        #endif
        #expect(loadNames.count > 50)
        let locator = InProcessDependencyLocator()

        var mismatchCount = 0
        for loadName in loadNames.sorted() {
            let bareImageName = DependencyLoadName.bareImageName(of: loadName)
            let expectedImage = bareImageName.isEmpty ? nil : MachOImage(name: bareImageName)
            let locatedImage = locator.locate(loadName: loadName)
            if locatedImage?.ptr != expectedImage?.ptr {
                mismatchCount += 1
                Issue.record("\(loadName): located \(String(describing: locatedImage?.ptr)), MachOImage(name:) \(String(describing: expectedImage?.ptr))")
            }
        }
        #expect(mismatchCount == 0)
    }
}
