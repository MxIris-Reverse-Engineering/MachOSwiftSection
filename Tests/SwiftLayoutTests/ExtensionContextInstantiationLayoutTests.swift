import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
@testable import SwiftLayout
import MachOTestingSupport

/// An instantiation of a type declared in a constrained extension names its
/// context as an extension: `DepthOuter<Int>.ConstrainedInner<String>`
/// demangles to `ConstrainedInner` under `Extension(<module>,
/// DepthOuter<Int>, <signature>)`, and the outer argument rides the
/// extension's extended type, not a nominal parent.
///
/// The argument walk stopped at the extension, so it saw only the innermost
/// list and bound `String` to depth 0 — `ConstrainedInner`'s
/// `InnerElement` (depth 1) stayed unsubstituted and the field naming the
/// instantiation, with every field after it, degraded to unknown.
@Suite
struct ExtensionContextInstantiationLayoutTests {
    private static let holderQualifiedTypeName = "\(GenericSpecializationFixture.moduleName).DepthHolder"

    @Test("an instantiation under an extension context lays out like the runtime's")
    func instantiationUnderExtensionContext() throws {
        let machOImage = try GenericSpecializationFixture.loadedImage()
        let runtimeOffsets = try #require(
            try runtimeFieldOffsets(ofQualifiedTypeName: Self.holderQualifiedTypeName, in: machOImage),
            "no runtime field-offset vector for DepthHolder"
        )

        let machOFile = try GenericSpecializationFixture.machOFile()
        let aggregate = try fieldLayout(
            ofQualifiedTypeName: Self.holderQualifiedTypeName,
            with: try StaticLayoutCalculator(machO: machOFile),
            in: machOFile
        )

        assertFullyComputed(aggregate, equals: runtimeOffsets, typeName: "DepthHolder")
    }
}
