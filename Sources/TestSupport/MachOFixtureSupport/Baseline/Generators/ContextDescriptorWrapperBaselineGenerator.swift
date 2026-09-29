import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ContextDescriptorWrapperBaseline.swift`.
///
/// `ContextDescriptorWrapper` is a 6-case sum type covering every kind of
/// context descriptor (type / protocol / anonymous / extension / module /
/// opaqueType). Members include 5 case-extraction accessors, 9 boolean
/// `is*` predicates, 4 alternate-projection vars (`contextDescriptor`,
/// `namedContextDescriptor`, `typeContextDescriptor`,
/// `typeContextDescriptorWrapper`), the `parent`/`genericContext` instance
/// methods, and the static `resolve` family.
///
/// **Scope decision:** This Suite asserts the wrapper's behaviour against
/// the `Structs.StructTest` representative (an `isStruct: true` instance,
/// every other `is*` accessor `false`). Broader kind coverage (a class /
/// enum / protocol / opaqueType variant) is deferred to the dedicated
/// concrete-kind Suites in Tasks 7-11; those Suites hit the wrapper through
/// their own pickers and round-trip the `is*` predicates implicitly.
package enum ContextDescriptorWrapperBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.struct_StructTest(in: machO)
        let wrapper = ContextDescriptorWrapper.type(.struct(descriptor))
        let entryExpr = try emitEntryExpr(for: wrapper, in: machO)

        // Public members declared directly in ContextDescriptorWrapper.swift.
        // The `resolve` static func family (Self vs Self?, MachO vs pointer
        // vs ReadingContext) collapses to one MethodKey under
        // PublicMemberScanner's name-only key.
        let registered = [
            "anonymousContextDescriptor",
            "contextDescriptor",
            "extensionContextDescriptor",
            "genericContext",
            "isAnonymous",
            "isClass",
            "isEnum",
            "isExtension",
            "isModule",
            "isOpaqueType",
            "isProtocol",
            "isStruct",
            "isType",
            "moduleContextDescriptor",
            "namedContextDescriptor",
            "opaqueTypeDescriptor",
            "parent",
            "protocolDescriptor",
            "resolve",
            "typeContextDescriptor",
            "typeContextDescriptorWrapper",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // Picker: `Structs.StructTest` — an `isStruct: true` representative.
        // Other `is*` accessors are all `false` for this picker; broader
        // kind coverage lives in the dedicated concrete-kind Suites.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ContextDescriptorWrapperBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let descriptorOffset: Int
                let isType: Bool
                let isStruct: Bool
                let isClass: Bool
                let isEnum: Bool
                let isProtocol: Bool
                let isAnonymous: Bool
                let isExtension: Bool
                let isModule: Bool
                let isOpaqueType: Bool
                let hasProtocolDescriptor: Bool
                let hasExtensionContextDescriptor: Bool
                let hasOpaqueTypeDescriptor: Bool
                let hasModuleContextDescriptor: Bool
                let hasAnonymousContextDescriptor: Bool
                let hasTypeContextDescriptor: Bool
                let hasTypeContextDescriptorWrapper: Bool
                let hasNamedContextDescriptor: Bool
                let hasParent: Bool
                let hasGenericContext: Bool
            }

            static let structTest = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ContextDescriptorWrapperBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(
        for wrapper: ContextDescriptorWrapper,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> String {
        let descriptorOffset = wrapper.contextDescriptor.offset
        let isType = wrapper.isType
        let isStruct = wrapper.isStruct
        let isClass = wrapper.isClass
        let isEnum = wrapper.isEnum
        let isProtocol = wrapper.isProtocol
        let isAnonymous = wrapper.isAnonymous
        let isExtension = wrapper.isExtension
        let isModule = wrapper.isModule
        let isOpaqueType = wrapper.isOpaqueType
        let hasProtocolDescriptor = wrapper.protocolDescriptor != nil
        let hasExtensionContextDescriptor = wrapper.extensionContextDescriptor != nil
        let hasOpaqueTypeDescriptor = wrapper.opaqueTypeDescriptor != nil
        let hasModuleContextDescriptor = wrapper.moduleContextDescriptor != nil
        let hasAnonymousContextDescriptor = wrapper.anonymousContextDescriptor != nil
        let hasTypeContextDescriptor = wrapper.typeContextDescriptor != nil
        let hasTypeContextDescriptorWrapper = wrapper.typeContextDescriptorWrapper != nil
        let hasNamedContextDescriptor = wrapper.namedContextDescriptor != nil
        let hasParent = (try wrapper.parent(in: machO)) != nil
        let hasGenericContext = (try wrapper.genericContext(in: machO)) != nil

        let expr: ExprSyntax = """
        Entry(
            descriptorOffset: \(raw: BaselineEmitter.hex(descriptorOffset)),
            isType: \(literal: isType),
            isStruct: \(literal: isStruct),
            isClass: \(literal: isClass),
            isEnum: \(literal: isEnum),
            isProtocol: \(literal: isProtocol),
            isAnonymous: \(literal: isAnonymous),
            isExtension: \(literal: isExtension),
            isModule: \(literal: isModule),
            isOpaqueType: \(literal: isOpaqueType),
            hasProtocolDescriptor: \(literal: hasProtocolDescriptor),
            hasExtensionContextDescriptor: \(literal: hasExtensionContextDescriptor),
            hasOpaqueTypeDescriptor: \(literal: hasOpaqueTypeDescriptor),
            hasModuleContextDescriptor: \(literal: hasModuleContextDescriptor),
            hasAnonymousContextDescriptor: \(literal: hasAnonymousContextDescriptor),
            hasTypeContextDescriptor: \(literal: hasTypeContextDescriptor),
            hasTypeContextDescriptorWrapper: \(literal: hasTypeContextDescriptorWrapper),
            hasNamedContextDescriptor: \(literal: hasNamedContextDescriptor),
            hasParent: \(literal: hasParent),
            hasGenericContext: \(literal: hasGenericContext)
        )
        """
        return expr.description
    }
}
