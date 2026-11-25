#if os(macOS)

import Darwin
import MachOKit
import ObjCMetadataSource
import SwiftSectionFixtureSupport
import SwiftTypeNameResolution
import Testing

/// `ImageDeclaredTypeNames` lists both kinds of names one image declares,
/// because `TypeDatabase` reads only the first source registered for an image
/// path (evolution proposal `private-cf-type-modules`).
@Suite
struct ImageDeclaredTypeNamesTests {
    /// IOSurface declares both under nearly one name: the Objective-C class
    /// `IOSurface`, and the CF type `IOSurfaceRef`, which keeps its `Ref` in
    /// Swift because the class already took the stripped name.
    @Test
    func listsTheObjectiveCClassAndTheCFTypeOfOneImage() async throws {
        let ioSurfacePath = "/System/Library/Frameworks/IOSurface.framework/Versions/A/IOSurface"
        _ = try #require(dlopen(ioSurfacePath, RTLD_LAZY), "IOSurface did not load")
        let (machOFile, _) = try ProcessImages.cacheFileAndLoadedImage(path: ioSurfacePath)
        let declaredTypeNames = try await ImageDeclaredTypeNames(machO: machOFile, imagePath: ioSurfacePath).declaredTypeNames()
        #expect(declaredTypeNames.contains("IOSurface"))
        #expect(declaredTypeNames.contains("IOSurfaceRef"))
    }
}

#endif
