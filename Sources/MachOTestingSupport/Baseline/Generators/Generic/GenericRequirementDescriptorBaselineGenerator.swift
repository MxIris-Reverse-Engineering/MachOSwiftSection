import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/GenericRequirementDescriptorBaseline.swift`.
///
/// `GenericRequirementDescriptor` is the per-requirement record carried in
/// the trailing `requirements` array of a generic context. Each descriptor
/// holds a `flags`, a `param: RelativeDirectPointer<MangledName>`, and a
/// `content: RelativeOffset` whose interpretation depends on `flags.kind`.
///
/// Fixture choices (one per kind branch the parser exercises):
///   - `GenericStructLayoutRequirement.requirements[0]` — kind `.layout`
///   - `GenericStructSwiftProtocolRequirement.requirements[0]` —
///     kind `.protocol` (Swift)
///   - `GenericStructObjCProtocolRequirement.requirements[0]` —
///     kind `.protocol` (ObjC)
///   - `BaseClassRequirementTest.requirements[0]` — kind `.baseClass`
///   - `SameTypeRequirementTest.requirements[0]` — kind `.sameType`
///
/// Each entry records the descriptor's offset, the flags rawValue (the
/// load-bearing scalar), and the requirement-content kind. Equality of
/// the resolved param/content payloads (mangled names, protocol pointers)
/// is asserted at runtime via `isContentEqual` cross-reader checks.
package enum GenericRequirementDescriptorBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let layoutDescriptor = try BaselineFixturePicker.struct_GenericStructLayoutRequirement(in: machO)
        let layoutReq = try requireFirstRequirement(of: layoutDescriptor, in: machO)

        let swiftProtocolDescriptor = try BaselineFixturePicker.struct_GenericStructSwiftProtocolRequirement(in: machO)
        let swiftProtocolReq = try requireFirstRequirement(of: swiftProtocolDescriptor, in: machO)

        let objcProtocolDescriptor = try BaselineFixturePicker.struct_GenericStructObjCProtocolRequirement(in: machO)
        let objcProtocolReq = try requireFirstRequirement(of: objcProtocolDescriptor, in: machO)

        let baseClassDescriptor = try BaselineFixturePicker.struct_BaseClassRequirementTest(in: machO)
        let baseClassReq = try requireFirstRequirement(of: baseClassDescriptor, in: machO)

        let sameTypeDescriptor = try BaselineFixturePicker.struct_SameTypeRequirementTest(in: machO)
        let sameTypeReq = try requireFirstRequirement(of: sameTypeDescriptor, in: machO)

        let layoutExpr = emitEntryExpr(for: layoutReq)
        let swiftProtocolExpr = emitEntryExpr(for: swiftProtocolReq)
        let objcProtocolExpr = emitEntryExpr(for: objcProtocolReq)
        let baseClassExpr = emitEntryExpr(for: baseClassReq)
        let sameTypeExpr = emitEntryExpr(for: sameTypeReq)

        // Public members declared directly in GenericRequirementDescriptor.swift.
        // The three `paramMangledName(in:)` overloads (MachO + InProcess +
        // ReadingContext) and the matching `type(in:)` / `resolvedContent(in:)` /
        // `isContentEqual(to:in:)` families collapse to one MethodKey each
        // under PublicMemberScanner's name-based deduplication.
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        let registered = [
            "content",
            "isContentEqual",
            "layout",
            "offset",
            "paramMangledName",
            "resolvedContent",
            "type",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum GenericRequirementDescriptorBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let flagsRawValue: UInt32
                let kindRawValue: UInt8
                let contentKindCase: String
            }

            static let layoutRequirement = \(raw: layoutExpr)

            static let swiftProtocolRequirement = \(raw: swiftProtocolExpr)

            static let objcProtocolRequirement = \(raw: objcProtocolExpr)

            static let baseClassRequirement = \(raw: baseClassExpr)

            static let sameTypeRequirement = \(raw: sameTypeExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("GenericRequirementDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func requireFirstRequirement(
        of descriptor: StructDescriptor,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> GenericRequirementDescriptor {
        let context = try required(try descriptor.typeGenericContext(in: machO))
        return try required(context.currentRequirements.first)
    }

    private static func emitEntryExpr(for requirement: GenericRequirementDescriptor) -> String {
        let offset = requirement.offset
        let flagsRawValue = requirement.layout.flags.rawValue
        let kindRawValue = requirement.layout.flags.kind.rawValue
        let contentKindCase = describeContentKind(requirement.content)

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            flagsRawValue: \(raw: BaselineEmitter.hex(flagsRawValue)),
            kindRawValue: \(raw: BaselineEmitter.hex(kindRawValue)),
            contentKindCase: \(literal: contentKindCase)
        )
        """
        return expr.description
    }

    /// Stable string label for the `GenericRequirementContent` discriminant.
    /// We don't embed the resolved payload (relative pointers, mangled
    /// names) — runtime cross-reader equality covers those.
    private static func describeContentKind(_ content: GenericRequirementContent) -> String {
        switch content {
        case .type: return "type"
        case .protocol: return "protocol"
        case .layout: return "layout"
        case .conformance: return "conformance"
        case .invertedProtocols: return "invertedProtocols"
        }
    }
}
