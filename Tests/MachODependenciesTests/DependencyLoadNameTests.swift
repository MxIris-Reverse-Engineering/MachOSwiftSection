import Foundation
import MachOKit
import Testing
@testable import MachODependencies

/// Pins the load-name → bare-image-name rule. It is a contract with MachOKit,
/// not a convenience: `MachOImage(name:)` compares the *same* reduction of
/// every mapped image's path, so any drift here silently turns the in-process
/// locator into a no-op (which is exactly how `SwiftInterfaceBuilderDependencies`'s
/// image initializer resolved nothing for its whole life — it handed the raw
/// load path to a bare-name lookup).
@Suite
struct DependencyLoadNameTests {
    @Test(arguments: [
        ("@rpath/SymbolTestsHelper.framework/Versions/A/SymbolTestsHelper", "SymbolTestsHelper"),
        ("/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation", "Foundation"),
        ("/usr/lib/swift/libswiftCore.dylib", "libswiftCore"),
        // The FIRST extension component is stripped, not the last — the rule
        // MachOKit applies, so `libobjc.A.dylib` keys as `libobjc`.
        ("/usr/lib/libobjc.A.dylib", "libobjc"),
        ("libc++.1.dylib", "libc++"),
        ("Foundation", "Foundation"),
        ("", ""),
    ])
    func bareImageNameStripsDirectoriesAndTheFirstExtension(loadName: String, expectedBareImageName: String) {
        #expect(DependencyLoadName.bareImageName(of: loadName) == expectedBareImageName)
    }

    /// The reduction must agree with `MachOImage(name:)` on a real mapped
    /// image: the stdlib is loaded in every Swift process, so its absolute
    /// load path — never matched raw — must resolve once normalized.
    @Test func bareImageNameIsWhatMachOImageLookupMatches() {
        let loadName = "/usr/lib/swift/libswiftCore.dylib"
        #expect(MachOImage(name: loadName) == nil, "the raw load path must NOT match — that is the trap this rule exists for")
        let image = MachOImage(name: DependencyLoadName.bareImageName(of: loadName))
        #expect(image != nil)
        #expect(image?.imagePath == loadName)
    }
}
