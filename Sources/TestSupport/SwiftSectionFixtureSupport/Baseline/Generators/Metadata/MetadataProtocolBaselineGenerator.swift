import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

/// Emits `__Baseline__/MetadataProtocolBaseline.swift`.
///
/// Per the protocol-extension attribution rule (see `BaselineGenerator.swift`),
/// every method declared in the multiple `extension MetadataProtocol { ... }`
/// blocks (and the constrained `extension MetadataProtocol where HeaderType:
/// TypeMetadataHeaderBaseProtocol { ... }` blocks) attributes to
/// `MetadataProtocol`, not to concrete metadatas. The (MachO, in-process,
/// ReadingContext) overload triples collapse to a single `MethodKey` under
/// PublicMemberScanner's name-only keying.
///
/// The Suite (`MetadataProtocolTests`) materialises a
/// `StructMetadata`-conforming carrier (`Structs.StructTest`) via a
/// MachOImage metadata accessor and asserts each method:
/// - Static factories (`createInMachO`, `createInProcess`) round-trip
///   `Metadata.self`-typed lookups against a runtime metatype.
/// - Wrapper accessors (`asMetadataWrapper`, `asMetadata`,
///   `asFullMetadata`) round-trip the offset.
/// - Pointer-flavoured `asMetatype()` recovers the original `Any.Type`.
/// - Property `kind` matches `MetadataKind.struct` for the StructTest
///   carrier.
/// - `valueWitnesses`/`typeLayout` resolve through the full-metadata
///   header.
/// - `isAnyExistentialType` is `false` for the struct carrier.
/// - `typeContextDescriptorWrapper` resolves to the StructTest descriptor.
package enum MetadataProtocolBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public members declared in `extension MetadataProtocol { ... }`
        // blocks (across body, in-process, and ReadingContext variants).
        // Overload pairs collapse to single MethodKey entries under
        // PublicMemberScanner's name-only key.
        let registered = [
            "asFullMetadata",
            "asMetadata",
            "asMetadataWrapper",
            "asMetatype",
            "createInMachO",
            "createInProcess",
            "isAnyExistentialType",
            "kind",
            "typeContextDescriptorWrapper",
            "typeLayout",
            "valueWitnesses",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // MetadataProtocol's extension members operate against a live
        // metadata carrier; the carrier comes from MachOImage's accessor
        // function. The companion Suite verifies the cross-reader equality
        // block at runtime against this name-only baseline.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum MetadataProtocolBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("MetadataProtocolBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
