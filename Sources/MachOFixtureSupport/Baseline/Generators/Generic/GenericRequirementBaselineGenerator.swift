import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/GenericRequirementBaseline.swift`.
///
/// `GenericRequirement` is the high-level wrapper around
/// `GenericRequirementDescriptor`. Beyond the descriptor itself it pre-resolves
/// `paramManagledName` and `content` (a `ResolvedGenericRequirementContent`).
/// We exercise the same set of fixture variants as the descriptor Suite so
/// each requirement-content branch has a wrapper-side baseline:
///   - layout
///   - protocol (Swift)
///   - protocol (ObjC)
///   - baseClass
///   - sameType
///
/// Each `Entry` records the descriptor offset (for cross-Suite anchoring)
/// and the resolved content discriminant. The mangled-name string parses
/// to a deep tree we don't embed; runtime cross-reader equality covers it.
package enum GenericRequirementBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let layoutDescriptor = try BaselineFixturePicker.struct_GenericStructLayoutRequirement(in: machO)
        let layoutReq = try makeRequirement(for: layoutDescriptor, in: machO)

        let swiftProtocolDescriptor = try BaselineFixturePicker.struct_GenericStructSwiftProtocolRequirement(in: machO)
        let swiftProtocolReq = try makeRequirement(for: swiftProtocolDescriptor, in: machO)

        let objcProtocolDescriptor = try BaselineFixturePicker.struct_GenericStructObjCProtocolRequirement(in: machO)
        let objcProtocolReq = try makeRequirement(for: objcProtocolDescriptor, in: machO)

        let baseClassDescriptor = try BaselineFixturePicker.struct_BaseClassRequirementTest(in: machO)
        let baseClassReq = try makeRequirement(for: baseClassDescriptor, in: machO)

        let sameTypeDescriptor = try BaselineFixturePicker.struct_SameTypeRequirementTest(in: machO)
        let sameTypeReq = try makeRequirement(for: sameTypeDescriptor, in: machO)

        let layoutExpr = emitEntryExpr(for: layoutReq)
        let swiftProtocolExpr = emitEntryExpr(for: swiftProtocolReq)
        let objcProtocolExpr = emitEntryExpr(for: objcProtocolReq)
        let baseClassExpr = emitEntryExpr(for: baseClassReq)
        let sameTypeExpr = emitEntryExpr(for: sameTypeReq)

        // Public members declared directly in GenericRequirement.swift.
        // The three `init(descriptor:in:)` overloads (MachO + InProcess +
        // ReadingContext) collapse to one MethodKey under PublicMemberScanner's
        // name-based deduplication; `init(descriptor:)` is the InProcess form.
        let registered = [
            "content",
            "descriptor",
            "init(descriptor:)",
            "init(descriptor:in:)",
            "paramManagledName",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum GenericRequirementBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let descriptorOffset: Int
                let resolvedContentCase: String
            }

            static let layoutRequirement = \(raw: layoutExpr)

            static let swiftProtocolRequirement = \(raw: swiftProtocolExpr)

            static let objcProtocolRequirement = \(raw: objcProtocolExpr)

            static let baseClassRequirement = \(raw: baseClassExpr)

            static let sameTypeRequirement = \(raw: sameTypeExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("GenericRequirementBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func makeRequirement(
        for descriptor: StructDescriptor,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> GenericRequirement {
        let context = try required(try descriptor.typeGenericContext(in: machO))
        let firstRequirement = try required(context.currentRequirements.first)
        return try GenericRequirement(descriptor: firstRequirement, in: machO)
    }

    private static func emitEntryExpr(for requirement: GenericRequirement) -> String {
        let descriptorOffset = requirement.descriptor.offset
        let resolvedContentCase = describeResolvedContent(requirement.content)

        let expr: ExprSyntax = """
        Entry(
            descriptorOffset: \(raw: BaselineEmitter.hex(descriptorOffset)),
            resolvedContentCase: \(literal: resolvedContentCase)
        )
        """
        return expr.description
    }

    private static func describeResolvedContent(_ content: ResolvedGenericRequirementContent) -> String {
        switch content {
        case .type: return "type"
        case .protocol: return "protocol"
        case .layout: return "layout"
        case .conformance: return "conformance"
        case .invertedProtocols: return "invertedProtocols"
        }
    }
}
