import Foundation
import Testing
import ArgumentParser
import SwiftSectionKit
@testable import swift_section

/// The library words its errors without naming options; the command line has
/// always named them, and reported a usage mistake as a `ValidationError`
/// (usage text, exit code 64) rather than a plain failure (exit code 1). The
/// translation keeps every message and exit code as it was.
@Suite
struct CommandLineErrorTranslationTests {
    @Test("A fat binary without -a names the option, and the slices")
    func fatBinary() {
        let translated = CommandLineErrorTranslation.translated(MachOSourceError.fatBinaryRequiresArchitecture(availableArchitectures: ["arm64", "x86_64"]))
        #expect((translated as? LocalizedError)?.errorDescription == "The file is a fat (universal) binary. You must specify an architecture using --architecture (-a). Available architectures: arm64, x86_64")
    }

    @Test("The other loading errors keep their historical wording", arguments: [
        (MachOSourceError.architectureNotFound(.arm64e), "The specified architecture is not found or supported."),
        (.dyldSharedCacheImageNotFound(.name("Foundation")), "The specified image was not found in the dyld shared cache."),
    ])
    func loadingErrors(error: MachOSourceError, expectedDescription: String) {
        #expect((CommandLineErrorTranslation.translated(error) as? LocalizedError)?.errorDescription == expectedDescription)
    }

    @Test("A snapshot document given to diff --interface is a usage error in diff's words")
    func diffAnnotatedInterface() {
        let translated = CommandLineErrorTranslation.translated(SnapshotSourceError.binaryRequired(path: "old.json"), annotatedInterfaceRequiresBinaries: { _ in
            "--interface needs two binaries; snapshot JSON inputs only support the change-list report."
        })
        #expect((translated as? ValidationError)?.message == "--interface needs two binaries; snapshot JSON inputs only support the change-list report.")
    }

    @Test("Without a wording for it, the snapshot-document error passes through")
    func snapshotErrorWithoutWording() {
        let translated = CommandLineErrorTranslation.translated(SnapshotSourceError.binaryRequired(path: "old.json"))
        #expect(translated as? SnapshotSourceError == .binaryRequired(path: "old.json"))
    }

    @Test("Errors the command line never reworded pass through unchanged")
    func unrelatedErrorsPassThrough() {
        let translated = CommandLineErrorTranslation.translated(ObjCDeclarationLookupError.declarationNotFound("NSString"))
        #expect(translated as? ObjCDeclarationLookupError == .declarationNotFound("NSString"))
    }
}
