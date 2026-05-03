import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/SingletonMetadataInitializationBaseline.swift`.
///
/// `SingletonMetadataInitialization` is the trailing-objects payload appended
/// to descriptors with the `hasSingletonMetadataInitialization` bit. It
/// carries three `RelativeOffset`s: `initializationCacheOffset`,
/// `incompleteMetadata`, and `completionFunction`. The bit fires for resilient
/// classes (those that cross module boundaries on inheritance) and certain
/// generic-class shapes; the `SymbolTestsCore` fixture's
/// `Classes.ExternalSwiftSubclassTest`, `Classes.ExternalObjCSubclassTest`,
/// and `GenericFieldLayout.GenericClass*InheritNSObject` declarations are
/// candidate carriers.
///
/// We discover a representative descriptor at generator runtime by walking
/// every class descriptor and picking the first one whose bit is set;
/// emitting only the relative-offset values keeps the baseline stable across
/// MachO rebuilds (the offsets are layout-invariant for a given fixture).
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum SingletonMetadataInitializationBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.class_singletonMetadataInitFirst(in: machO)
        let classObject = try Class(descriptor: descriptor, in: machO)
        let initialization = try required(classObject.singletonMetadataInitialization)

        let entryExpr = emitEntryExpr(for: initialization, descriptorOffset: descriptor.offset)

        let registered = [
            "layout",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // The picker selects the first ClassDescriptor in SymbolTestsCore that
        // carries the hasSingletonMetadataInitialization bit. Relative offsets
        // are layout-invariant for a fixed source so the baseline stays
        // stable across rebuilds.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum SingletonMetadataInitializationBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            /// `RelativeOffset` is `Int32`; we store it as `UInt64`
            /// (bitPattern) here because `BaselineEmitter.hex` sign-extends
            /// to UInt64, so negative Int32 values would not fit a signed
            /// Int64 literal. The Suite reads the field via
            /// `Int32(truncatingIfNeeded:)` to recover the signed value.
            struct Entry {
                let descriptorOffset: Int
                let initializationCacheRelativeOffsetBits: UInt64
                let incompleteMetadataRelativeOffsetBits: UInt64
                let completionFunctionRelativeOffsetBits: UInt64
            }

            static let firstSingletonInit = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("SingletonMetadataInitializationBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(
        for initialization: SingletonMetadataInitialization,
        descriptorOffset: Int
    ) -> String {
        // RelativeOffset is `Int32`; the layout fields are the raw signed
        // offsets relative to the descriptor. We emit them as UInt64
        // bitPatterns since the hex helper sign-extends to UInt64 (negative
        // Int32 values overflow a signed Int64 literal).
        let cache = initialization.layout.initializationCacheOffset
        let incomplete = initialization.layout.incompleteMetadata
        let completion = initialization.layout.completionFunction

        let expr: ExprSyntax = """
        Entry(
            descriptorOffset: \(raw: BaselineEmitter.hex(descriptorOffset)),
            initializationCacheRelativeOffsetBits: \(raw: BaselineEmitter.hex(cache)),
            incompleteMetadataRelativeOffsetBits: \(raw: BaselineEmitter.hex(incomplete)),
            completionFunctionRelativeOffsetBits: \(raw: BaselineEmitter.hex(completion))
        )
        """
        return expr.description
    }
}
