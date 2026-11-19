import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/DispatchClassMetadataBaseline.swift`.
///
/// Phase C4: `DispatchClassMetadata` is exercised in the test as a real
/// InProcess wrapper resolved against `Classes.ClassTest.self`'s runtime
/// class metadata. Its observable state (the `kind` slot — descriptor /
/// isa pointer — and the `offset` slot — runtime metadata pointer
/// bit-pattern) is ASLR-randomized per process invocation, so no ABI
/// literal can be pinned here. The Suite asserts non-zero / decoded-kind
/// invariants instead.
///
/// `DispatchClassMetadata` mirrors the layout of `dispatch_object_t` /
/// `OS_object`-rooted runtime objects (libdispatch's class layout used
/// for ObjC interop with `dispatch_*` types). SymbolTestsCore declares
/// no `dispatch_*` carrier; the test reuses an arbitrary Swift class
/// metadata pointer to exercise the wrapper's accessor surface.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum DispatchClassMetadataBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let registered = [
            "layout",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source fixture: SymbolTestsCore.framework
        //
        // DispatchClassMetadata mirrors libdispatch's runtime class
        // layout (OS_object). It's not a Swift type descriptor and no
        // static carrier is reachable from SymbolTestsCore. The Suite
        // resolves the wrapper against `Classes.ClassTest.self`'s runtime
        // class metadata pointer (via dlsym + the C metadata accessor)
        // and exercises the wrapper accessor surface. No ABI literal is
        // pinned because the `kind` slot is the descriptor / isa pointer
        // and the `offset` slot is the runtime metadata pointer
        // bit-pattern — both ASLR-randomized per process.
        //
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum DispatchClassMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("DispatchClassMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
