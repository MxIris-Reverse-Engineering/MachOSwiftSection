import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ClassBaseline.swift` from the `SymbolTestsCore`
/// fixture via the MachOFile reader.
///
/// `Class` is the high-level wrapper around `ClassDescriptor`. It carries
/// many `Optional` ivars and array-shaped trailing tables (vtable / override
/// table / canonical specialized metadatas / etc.). We use the
/// **presence-flag** pattern (no value embedding) for the optionals because
/// the underlying types (`TypeGenericContext`, `MethodDescriptor`, etc.)
/// are not cheaply Equatable; presence + cardinality catches the structural
/// invariant we care about.
///
/// The `classTest` picker exercises a plain Swift class with a vtable and
/// no resilient superclass; `subclassTest` exercises an override table.
package enum ClassBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let classTestDescriptor = try BaselineFixturePicker.class_ClassTest(in: machO)
        let subclassTestDescriptor = try BaselineFixturePicker.class_SubclassTest(in: machO)

        let classTestClass = try Class(descriptor: classTestDescriptor, in: machO)
        let subclassTestClass = try Class(descriptor: subclassTestDescriptor, in: machO)

        let classTestExpr = emitEntryExpr(for: classTestClass)
        let subclassTestExpr = emitEntryExpr(for: subclassTestClass)

        // Public ivars + initializers declared directly in Class.swift.
        // Two `init(descriptor:in:)` overloads (MachO + Context) collapse to
        // a single MethodKey under PublicMemberScanner's name-based key.
        let registered = [
            "canonicalSpecializedMetadataAccessors",
            "canonicalSpecializedMetadatas",
            "canonicalSpecializedMetadatasCachingOnceToken",
            "canonicalSpecializedMetadatasListCount",
            "descriptor",
            "foreignMetadataInitialization",
            "genericContext",
            "init(descriptor:)",
            "init(descriptor:in:)",
            "invertibleProtocolSet",
            "methodDefaultOverrideDescriptors",
            "methodDefaultOverrideTableHeader",
            "methodDescriptors",
            "methodOverrideDescriptors",
            "objcResilientClassStubInfo",
            "overrideTableHeader",
            "resilientSuperclass",
            "singletonMetadataInitialization",
            "singletonMetadataPointer",
            "vTableDescriptorHeader",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ClassBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let descriptorOffset: Int
                let hasGenericContext: Bool
                let hasResilientSuperclass: Bool
                let hasForeignMetadataInitialization: Bool
                let hasSingletonMetadataInitialization: Bool
                let hasVTableDescriptorHeader: Bool
                let methodDescriptorsCount: Int
                let hasOverrideTableHeader: Bool
                let methodOverrideDescriptorsCount: Int
                let hasObjCResilientClassStubInfo: Bool
                let hasCanonicalSpecializedMetadatasListCount: Bool
                let canonicalSpecializedMetadatasCount: Int
                let canonicalSpecializedMetadataAccessorsCount: Int
                let hasCanonicalSpecializedMetadatasCachingOnceToken: Bool
                let hasInvertibleProtocolSet: Bool
                let hasSingletonMetadataPointer: Bool
                let hasMethodDefaultOverrideTableHeader: Bool
                let methodDefaultOverrideDescriptorsCount: Int
            }

            static let classTest = \(raw: classTestExpr)

            static let subclassTest = \(raw: subclassTestExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ClassBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for instance: Class) -> String {
        let descriptorOffset = instance.descriptor.offset
        let hasGenericContext = instance.genericContext != nil
        let hasResilientSuperclass = instance.resilientSuperclass != nil
        let hasForeignMetadataInitialization = instance.foreignMetadataInitialization != nil
        let hasSingletonMetadataInitialization = instance.singletonMetadataInitialization != nil
        let hasVTableDescriptorHeader = instance.vTableDescriptorHeader != nil
        let methodDescriptorsCount = instance.methodDescriptors.count
        let hasOverrideTableHeader = instance.overrideTableHeader != nil
        let methodOverrideDescriptorsCount = instance.methodOverrideDescriptors.count
        let hasObjCResilientClassStubInfo = instance.objcResilientClassStubInfo != nil
        let hasCanonicalSpecializedMetadatasListCount = instance.canonicalSpecializedMetadatasListCount != nil
        let canonicalSpecializedMetadatasCount = instance.canonicalSpecializedMetadatas.count
        let canonicalSpecializedMetadataAccessorsCount = instance.canonicalSpecializedMetadataAccessors.count
        let hasCanonicalSpecializedMetadatasCachingOnceToken = instance.canonicalSpecializedMetadatasCachingOnceToken != nil
        let hasInvertibleProtocolSet = instance.invertibleProtocolSet != nil
        let hasSingletonMetadataPointer = instance.singletonMetadataPointer != nil
        let hasMethodDefaultOverrideTableHeader = instance.methodDefaultOverrideTableHeader != nil
        let methodDefaultOverrideDescriptorsCount = instance.methodDefaultOverrideDescriptors.count

        let expr: ExprSyntax = """
        Entry(
            descriptorOffset: \(raw: BaselineEmitter.hex(descriptorOffset)),
            hasGenericContext: \(literal: hasGenericContext),
            hasResilientSuperclass: \(literal: hasResilientSuperclass),
            hasForeignMetadataInitialization: \(literal: hasForeignMetadataInitialization),
            hasSingletonMetadataInitialization: \(literal: hasSingletonMetadataInitialization),
            hasVTableDescriptorHeader: \(literal: hasVTableDescriptorHeader),
            methodDescriptorsCount: \(literal: methodDescriptorsCount),
            hasOverrideTableHeader: \(literal: hasOverrideTableHeader),
            methodOverrideDescriptorsCount: \(literal: methodOverrideDescriptorsCount),
            hasObjCResilientClassStubInfo: \(literal: hasObjCResilientClassStubInfo),
            hasCanonicalSpecializedMetadatasListCount: \(literal: hasCanonicalSpecializedMetadatasListCount),
            canonicalSpecializedMetadatasCount: \(literal: canonicalSpecializedMetadatasCount),
            canonicalSpecializedMetadataAccessorsCount: \(literal: canonicalSpecializedMetadataAccessorsCount),
            hasCanonicalSpecializedMetadatasCachingOnceToken: \(literal: hasCanonicalSpecializedMetadatasCachingOnceToken),
            hasInvertibleProtocolSet: \(literal: hasInvertibleProtocolSet),
            hasSingletonMetadataPointer: \(literal: hasSingletonMetadataPointer),
            hasMethodDefaultOverrideTableHeader: \(literal: hasMethodDefaultOverrideTableHeader),
            methodDefaultOverrideDescriptorsCount: \(literal: methodDefaultOverrideDescriptorsCount)
        )
        """
        return expr.description
    }
}
