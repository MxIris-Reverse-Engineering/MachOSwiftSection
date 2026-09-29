import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ObjCResilientClassStubInfoBaseline.swift`.
///
/// `ObjCResilientClassStubInfo` is the trailing-object payload that holds
/// a `RelativeDirectRawPointer` to the resilient class stub. It only
/// appears when a class has `hasObjCResilientClassStub == true`, which
/// fires when ObjC interop is on AND the class is non-generic AND its
/// metadata strategy is `Resilient` or `Singleton` (i.e. the metadata
/// requires runtime relocation).
///
/// Phase B4 introduced `ObjCResilientStubFixtures.ResilientObjCStubChild`
/// (a Swift class inheriting `SymbolTestsHelper.Object`) as the canonical
/// carrier. Cross-module inheritance from a class declared in another
/// `BUILD_LIBRARY_FOR_DISTRIBUTION = YES` module triggers the resilient
/// metadata strategy, so the descriptor carries the trailing record.
package enum ObjCResilientClassStubInfoBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        // Public members declared directly in ObjCResilientClassStubInfo.swift.
        // `init(layout:offset:)` is filtered as memberwise-synthesized;
        // `stub` is the inner Layout's stored field, exercised
        // transitively via the `layout` test.
        let registered = [
            "layout",
            "offset",
        ]

        let descriptor = try BaselineFixturePicker.class_ResilientObjCStubChild(in: machO)
        let classWrapper = try Class(descriptor: descriptor, in: machO)
        let stubInfo = try required(classWrapper.objcResilientClassStubInfo)

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // ObjCResilientClassStubInfo is the trailing-object record on a
        // class whose metadata strategy is Resilient/Singleton (i.e. the
        // metadata requires runtime relocation/initialization). The
        // Suite drives `ObjCResilientStubFixtures.ResilientObjCStubChild`
        // (parent `SymbolTestsHelper.Object`, cross-module) and asserts
        // cross-reader agreement on the record offset and the stub
        // reference's relative-offset scalar.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ObjCResilientClassStubInfoBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let sourceClassOffset: Int
                let offset: Int
                let layoutStubRelativeOffset: Int32
            }

            static let resilientObjCStubChild = Entry(
                sourceClassOffset: \(raw: BaselineEmitter.hex(descriptor.offset)),
                offset: \(raw: BaselineEmitter.hex(stubInfo.offset)),
                layoutStubRelativeOffset: \(literal: stubInfo.layout.stub.relativeOffset)
            )
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ObjCResilientClassStubInfoBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
