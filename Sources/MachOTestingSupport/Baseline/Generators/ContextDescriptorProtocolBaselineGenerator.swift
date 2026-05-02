import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ContextDescriptorProtocolBaseline.swift`.
///
/// Per the protocol-extension attribution rule (see `BaselineGenerator.swift`),
/// `parent`, `genericContext`, `moduleContextDesciptor`,
/// `isCImportedContextDescriptor`, and `subscript(dynamicMember:)` all live
/// on `ContextDescriptorProtocol` and are exercised here, NOT on the
/// concrete-descriptor Suites.
///
/// The methods return live optionals (descriptor wrappers, generic contexts,
/// module descriptors) we don't embed as literals; instead the companion
/// Suite verifies cross-reader-consistent results at runtime against the
/// presence flags recorded here. The dynamic-member `subscript` is exercised
/// indirectly by going through the subscript syntax (`descriptor.kind`).
package enum ContextDescriptorProtocolBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machO)
        let hasParent = (try descriptor.parent(in: machO)) != nil
        let hasGenericContext = try descriptor.genericContext(in: machO) != nil
        let hasModuleContextDescriptor = try descriptor.moduleContextDesciptor(in: machO) != nil
        let isCImported = try descriptor.isCImportedContextDescriptor(in: machO)
        // The dynamic-member subscript routes to `layout.flags`; pick a stable
        // scalar (`kind.rawValue`) to assert against.
        let subscriptKindRawValue = descriptor.kind.rawValue

        let entryExpr = emitEntryExpr(
            hasParent: hasParent,
            hasGenericContext: hasGenericContext,
            hasModuleContextDescriptor: hasModuleContextDescriptor,
            isCImported: isCImported,
            subscriptKindRawValue: subscriptKindRawValue
        )

        // Public members in protocol body + protocol extensions on
        // `ContextDescriptorProtocol`. Each name collapses to one MethodKey
        // under PublicMemberScanner's name-only key, so the various MachO/
        // InProcess/ReadingContext overloads of `parent`/`genericContext`/
        // etc. flatten into single entries.
        let registered = [
            "genericContext",
            "isCImportedContextDescriptor",
            "moduleContextDesciptor",
            "parent",
            "subscript(dynamicMember:)",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // Live wrapper payloads (parent/genericContext/moduleContextDescriptor)
        // aren't embedded as literals; the companion Suite
        // (ContextDescriptorProtocolTests) verifies the methods produce
        // cross-reader-consistent results at runtime.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ContextDescriptorProtocolBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let hasParent: Bool
                let hasGenericContext: Bool
                let hasModuleContextDescriptor: Bool
                let isCImportedContextDescriptor: Bool
                let subscriptKindRawValue: UInt8
            }

            static let structTest = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ContextDescriptorProtocolBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(
        hasParent: Bool,
        hasGenericContext: Bool,
        hasModuleContextDescriptor: Bool,
        isCImported: Bool,
        subscriptKindRawValue: UInt8
    ) -> String {
        let expr: ExprSyntax = """
        Entry(
            hasParent: \(literal: hasParent),
            hasGenericContext: \(literal: hasGenericContext),
            hasModuleContextDescriptor: \(literal: hasModuleContextDescriptor),
            isCImportedContextDescriptor: \(literal: isCImported),
            subscriptKindRawValue: \(raw: BaselineEmitter.hex(subscriptKindRawValue))
        )
        """
        return expr.description
    }
}
