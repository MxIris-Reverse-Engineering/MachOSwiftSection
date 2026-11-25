#if os(macOS)

import Darwin
import Foundation
import MachOKit
import SwiftSectionFixtureSupport
import SwiftTypeNameResolution
import Testing

/// `CFDeclaredTypeNames` names the CF types an image defines after the
/// `…GetTypeID` functions it exports (evolution proposal
/// `private-cf-type-modules`).
@Suite
struct CFDeclaredTypeNamesTests {
    /// Two type-ID functions — one spelled as a private function, with a
    /// leading underscore — beside exports that name no type: a function of
    /// the type that is not its type-ID function, and type-ID functions with
    /// no type name before the suffix.
    private static let fixtureSource = """
    unsigned long ProbeWidgetGetTypeID(void) { return 1; }
    unsigned long _ProbeSecretGetTypeID(void) { return 2; }
    void *ProbeWidgetCreate(void) { return 0; }
    unsigned long GetTypeID(void) { return 3; }
    unsigned long __GetTypeID(void) { return 4; }
    """

    /// What the fixture defines, written out by hand: each type-ID function's
    /// typedef, and the private one's unprefixed spelling too.
    private static let fixtureTypedefNames: Set<String> = ["ProbeWidgetRef", "_ProbeSecretRef", "ProbeSecretRef"]

    private static let fixtureImagePath = "/Library/Frameworks/ProbeCF.framework/ProbeCF"

    private static func fixtureLibraryURL() throws -> URL {
        try FixtureCompiler.shared.dynamicLibrary(named: "CFDeclaredTypeNamesFixture", language: .c, source: fixtureSource)
    }

    @Test
    func fileNamesTheTypedefOfEveryExportedTypeIDFunction() async throws {
        let machOFile = try HostSlice.machOFile(at: Self.fixtureLibraryURL())
        let declaredTypeNames = await CFDeclaredTypeNames(machO: machOFile, imagePath: Self.fixtureImagePath).declaredTypeNames()
        #expect(Set(declaredTypeNames) == Self.fixtureTypedefNames)
    }

    @Test
    func loadedImageNamesTheSameTypedefs() async throws {
        let libraryURL = try Self.fixtureLibraryURL()
        let libraryHandle = try #require(dlopen(libraryURL.path, RTLD_LAZY), "the fixture library did not load")
        let typeIDFunctionAddress = try #require(dlsym(libraryHandle, "ProbeWidgetGetTypeID"))
        let machOImage = try #require(ProcessImages.image(containing: typeIDFunctionAddress))
        let declaredTypeNames = await CFDeclaredTypeNames(machO: machOImage, imagePath: Self.fixtureImagePath).declaredTypeNames()
        #expect(Set(declaredTypeNames) == Self.fixtureTypedefNames)
    }

    /// The case the source exists for: CoreSVG is a private framework, so no
    /// SDK header declares `CGSVGDocumentRef`, and SwiftUICore's references to
    /// it found no module until CoreSVG's export of `CGSVGDocumentGetTypeID`
    /// was read. Read from this Mac's shared cache and as loaded in-process.
    @Test
    func coreSVGDeclaresItsPrivateDocumentType() async throws {
        let coreSVGPath = "/System/Library/PrivateFrameworks/CoreSVG.framework/Versions/A/CoreSVG"
        _ = try #require(dlopen(coreSVGPath, RTLD_LAZY), "CoreSVG did not load")
        let (machOFile, machOImage) = try ProcessImages.cacheFileAndLoadedImage(path: coreSVGPath)
        let fileTypeNames = await CFDeclaredTypeNames(machO: machOFile, imagePath: coreSVGPath).declaredTypeNames()
        let imageTypeNames = await CFDeclaredTypeNames(machO: machOImage, imagePath: coreSVGPath).declaredTypeNames()
        #expect(fileTypeNames.contains("CGSVGDocumentRef"))
        #expect(imageTypeNames.contains("CGSVGDocumentRef"))
    }
}

#endif
