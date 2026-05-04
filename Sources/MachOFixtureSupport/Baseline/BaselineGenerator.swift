import Foundation
import MachOExtensions
import MachOFoundation
import MachOKit
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Top-level dispatcher for the per-suite baseline sub-generators.
///
/// Each `Models/<dir>/<File>.swift` produces a corresponding
/// `<File>Baseline.swift` literal under `__Baseline__/`. The dispatcher's only
/// jobs are loading the fixture MachOFile and routing to the right
/// sub-generator.
///
/// Pilot scope (Task 4): only `Type/Struct/` Suites. Tasks 5-15 each add one
/// `case` to `dispatchSuite` and one `try dispatchSuite(...)` line to
/// `generateAll`.
///
/// **Protocol-extension method attribution rule.**
///
/// `PublicMemberScanner` attributes a method's `MethodKey.typeName` based on the
/// `extendedType` of its enclosing `extension`, NOT the file it lives in.
///
/// Example: `Extension/ExtensionContextDescriptor.swift` contains
/// `extension ExtensionContextDescriptorProtocol { public func extendedContext(in:) ... }`.
/// The scanner emits `MethodKey(typeName: "ExtensionContextDescriptorProtocol",
/// memberName: "extendedContext")`. The Suite/baseline for that method must be
/// `ExtensionContextDescriptorProtocolBaseline` / `ExtensionContextDescriptorProtocolTests`,
/// regardless of which file the extension is declared in.
///
/// When adding a new sub-generator/Suite, look at the actual `extension` declarations,
/// not just the file structure under `Models/<dir>/`.
package enum BaselineGenerator {
    /// Regenerates every baseline file in deterministic order. Idempotent —
    /// calling twice in a row leaves `__Baseline__/` byte-identical.
    package static func generateAll(outputDirectory: URL) async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let machOFile = try loadFixtureMachOFile()
        // Anonymous/
        try dispatchSuite("AnonymousContext", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("AnonymousContextDescriptor", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("AnonymousContextDescriptorFlags", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("AnonymousContextDescriptorProtocol", in: machOFile, outputDirectory: outputDirectory)
        // ContextDescriptor/
        try dispatchSuite("ContextDescriptor", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ContextDescriptorFlags", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ContextDescriptorKind", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ContextDescriptorKindSpecificFlags", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ContextDescriptorProtocol", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ContextDescriptorWrapper", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ContextProtocol", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ContextWrapper", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("NamedContextDescriptorProtocol", in: machOFile, outputDirectory: outputDirectory)
        // Extension/
        try dispatchSuite("ExtensionContext", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ExtensionContextDescriptor", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ExtensionContextDescriptorProtocol", in: machOFile, outputDirectory: outputDirectory)
        // Module/
        try dispatchSuite("ModuleContext", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ModuleContextDescriptor", in: machOFile, outputDirectory: outputDirectory)
        // Type/Struct/
        try dispatchSuite("StructDescriptor", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("Struct", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("StructMetadata", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("StructMetadataProtocol", in: machOFile, outputDirectory: outputDirectory)
        // Type/Class/ — sub-generators live in Generators/Class/.
        // The Class group is large (~22 files) so the source files are
        // grouped under Generators/Class/ for readability; flat naming is
        // retained for the smaller groups (Tasks 4-6).
        try dispatchSuite("AnyClassMetadata", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("AnyClassMetadataObjCInterop", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("AnyClassMetadataObjCInteropProtocol", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("AnyClassMetadataProtocol", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("Class", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ClassDescriptor", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ClassFlags", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ClassMetadata", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ClassMetadataBounds", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ClassMetadataBoundsProtocol", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ClassMetadataObjCInterop", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ExtraClassDescriptorFlags", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("FinalClassMetadataProtocol", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("MethodDefaultOverrideDescriptor", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("MethodDefaultOverrideTableHeader", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("MethodDescriptor", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("MethodDescriptorFlags", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("MethodDescriptorKind", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("MethodOverrideDescriptor", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ObjCClassWrapperMetadata", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ObjCResilientClassStubInfo", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("OverrideTableHeader", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ResilientSuperclass", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("StoredClassMetadataBounds", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("VTableDescriptorHeader", in: machOFile, outputDirectory: outputDirectory)
        // Type/Enum/ — sub-generators live in Generators/Enum/, mirroring
        // the Type/Class/ layout convention from Task 7.
        try dispatchSuite("Enum", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("EnumDescriptor", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("EnumFunctions", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("EnumMetadata", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("EnumMetadataProtocol", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("MultiPayloadEnumDescriptor", in: machOFile, outputDirectory: outputDirectory)
        // Type/ root — sub-generators live in Generators/Type/, mirroring
        // the Type/Class/ and Type/Enum/ layout conventions from Tasks 7-8.
        try dispatchSuite("TypeContextDescriptor", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("TypeContextDescriptorFlags", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("TypeContextDescriptorProtocol", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("TypeContextDescriptorWrapper", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("TypeContextWrapper", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("TypeMetadataRecord", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("TypeReference", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ValueMetadata", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ValueMetadataProtocol", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ValueTypeDescriptorWrapper", in: machOFile, outputDirectory: outputDirectory)
        // Protocol/ — sub-generators live in Generators/Protocol/, with
        // Invertible/ and ObjC/ subdirectories mirroring the source layout.
        try dispatchSuite("InvertibleProtocolSet", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("InvertibleProtocolsRequirementCount", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ObjCProtocolPrefix", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("Protocol", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ProtocolBaseRequirement", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ProtocolContextDescriptorFlags", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ProtocolDescriptor", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ProtocolDescriptorFlags", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ProtocolDescriptorRef", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ProtocolRecord", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ProtocolRequirement", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ProtocolRequirementFlags", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ProtocolRequirementKind", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ProtocolWitnessTable", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("RelativeObjCProtocolPrefix", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ResilientWitness", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ResilientWitnessesHeader", in: machOFile, outputDirectory: outputDirectory)
        // ProtocolConformance/ — sub-generators live in
        // Generators/ProtocolConformance/, mirroring the Type/Class/,
        // Type/Enum/, Type/, and Protocol/ layout conventions from
        // Tasks 7-10.
        try dispatchSuite("GlobalActorReference", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ProtocolConformance", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ProtocolConformanceDescriptor", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ProtocolConformanceFlags", in: machOFile, outputDirectory: outputDirectory)
        // Generic/ — sub-generators live in Generators/Generic/, mirroring
        // the Type/Class/, Type/Enum/, Type/, Protocol/, and
        // ProtocolConformance/ layout conventions from Tasks 7-11.
        try dispatchSuite("GenericContext", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("GenericContextDescriptorFlags", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("GenericContextDescriptorHeader", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("GenericEnvironment", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("GenericEnvironmentFlags", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("GenericPackShapeDescriptor", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("GenericPackShapeHeader", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("GenericParamDescriptor", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("GenericRequirement", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("GenericRequirementContent", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("GenericRequirementDescriptor", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("GenericRequirementFlags", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("GenericValueDescriptor", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("GenericValueHeader", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("GenericWitnessTable", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("TypeGenericContextDescriptorHeader", in: machOFile, outputDirectory: outputDirectory)
        // FieldDescriptor/ — sub-generators live in Generators/FieldDescriptor/.
        // FieldDescriptorKind is a pure enum (only `case` declarations, no
        // public func/var/init), so PublicMemberScanner emits no MethodKey
        // entries for it — no Suite/baseline is needed.
        try dispatchSuite("FieldDescriptor", in: machOFile, outputDirectory: outputDirectory)
        // FieldRecord/ — sub-generators live in Generators/FieldRecord/.
        try dispatchSuite("FieldRecord", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("FieldRecordFlags", in: machOFile, outputDirectory: outputDirectory)
        // AssociatedType/ — sub-generators live in Generators/AssociatedType/.
        try dispatchSuite("AssociatedType", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("AssociatedTypeDescriptor", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("AssociatedTypeRecord", in: machOFile, outputDirectory: outputDirectory)
        // Metadata/ — sub-generators live in Generators/Metadata/, with
        // Headers/ and MetadataInitialization/ subdirectories mirroring
        // the source layout. Most metadata types are runtime-only or
        // require a MachOImage accessor invocation; baselines emit only
        // registered names where live data isn't reachable from the
        // static section walks. Pure enums (`MetadataKind`, `MetadataState`)
        // and marker protocols (`HeapMetadataProtocol`,
        // `HeapMetadataHeaderProtocol`, `HeapMetadataHeaderPrefixProtocol`,
        // `TypeMetadataHeaderProtocol`, `TypeMetadataHeaderBaseProtocol`,
        // `TypeMetadataLayoutPrefixProtocol`) carry no public extension
        // members so PublicMemberScanner emits no MethodKey entries —
        // no Suite/baseline is needed.
        try dispatchSuite("CanonicalSpecializedMetadataAccessorsListEntry", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("CanonicalSpecializedMetadatasCachingOnceToken", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("CanonicalSpecializedMetadatasListCount", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("CanonicalSpecializedMetadatasListEntry", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("FixedArrayTypeMetadata", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("FullMetadata", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("Metadata", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("MetadataAccessorFunction", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("MetadataBounds", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("MetadataBoundsProtocol", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("MetadataProtocol", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("MetadataRequest", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("MetadataResponse", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("MetadataWrapper", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("MetatypeMetadata", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("SingletonMetadataPointer", in: machOFile, outputDirectory: outputDirectory)
        // Metadata/Headers/
        try dispatchSuite("HeapMetadataHeader", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("HeapMetadataHeaderPrefix", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("TypeMetadataHeader", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("TypeMetadataHeaderBase", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("TypeMetadataLayoutPrefix", in: machOFile, outputDirectory: outputDirectory)
        // Metadata/MetadataInitialization/
        try dispatchSuite("ForeignMetadataInitialization", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("SingletonMetadataInitialization", in: machOFile, outputDirectory: outputDirectory)
        // BuiltinType/
        try dispatchSuite("BuiltinType", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("BuiltinTypeDescriptor", in: machOFile, outputDirectory: outputDirectory)
        // DispatchClass/
        try dispatchSuite("DispatchClassMetadata", in: machOFile, outputDirectory: outputDirectory)
        // ExistentialType/
        try dispatchSuite("ExistentialMetatypeMetadata", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ExistentialTypeFlags", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ExistentialTypeMetadata", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ExtendedExistentialTypeMetadata", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ExtendedExistentialTypeShape", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ExtendedExistentialTypeShapeFlags", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("NonUniqueExtendedExistentialTypeShape", in: machOFile, outputDirectory: outputDirectory)
        // ForeignType/ — registration-only; SymbolTestsCore declares no
        // CF/ObjC foreign-class bridges or foreign-reference-type imports.
        try dispatchSuite("ForeignClassMetadata", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ForeignReferenceTypeMetadata", in: machOFile, outputDirectory: outputDirectory)
        // Function/ — FunctionTypeMetadata is runtime-allocated only.
        try dispatchSuite("FunctionTypeFlags", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("FunctionTypeMetadata", in: machOFile, outputDirectory: outputDirectory)
        // Heap/ — both metadata types are runtime-allocated only.
        try dispatchSuite("GenericBoxHeapMetadata", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("HeapLocalVariableMetadata", in: machOFile, outputDirectory: outputDirectory)
        // Mangling/ — MangledNameKind is a pure enum (no public func/var/init),
        // so only MangledName needs a Suite.
        try dispatchSuite("MangledName", in: machOFile, outputDirectory: outputDirectory)
        // OpaqueType/ — OpaqueMetadata is runtime-allocated only.
        try dispatchSuite("OpaqueMetadata", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("OpaqueType", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("OpaqueTypeDescriptor", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("OpaqueTypeDescriptorProtocol", in: machOFile, outputDirectory: outputDirectory)
        // TupleType/ — TupleTypeMetadata is runtime-allocated only;
        // TupleTypeMetadata.Element gets its own Suite (testedTypeName ==
        // "Element") because PublicMemberScanner keys nested types by
        // their inner struct name.
        try dispatchSuite("TupleTypeMetadata", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("TupleTypeMetadataElement", in: machOFile, outputDirectory: outputDirectory)
        // ValueWitnessTable/
        try dispatchSuite("TypeLayout", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ValueWitnessFlags", in: machOFile, outputDirectory: outputDirectory)
        try dispatchSuite("ValueWitnessTable", in: machOFile, outputDirectory: outputDirectory)
        // Capture/ and Misc/ are skipped:
        //   - Capture/Capture.swift / CaptureDescriptor.swift declare no
        //     public surface (both are essentially placeholder files).
        //   - Misc/SpecialPointerAuthDiscriminators.swift uses package-
        //     scoped declarations only, so PublicMemberScanner emits no
        //     entries for it.

        // Index of every Suite type registered above. Consumed by
        // MachOSwiftSectionCoverageInvariantTests (Task 16) to enumerate
        // `[any FixtureSuite.Type]` for the static-vs-runtime guard.
        try writeAllFixtureSuitesIndex(outputDirectory: outputDirectory)
    }

    /// Regenerates a single Suite's baseline file. Used by the polished
    /// `--suite` CLI flag (Task 17).
    package static func generate(suite name: String, outputDirectory: URL) async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let machOFile = try loadFixtureMachOFile()
        try dispatchSuite(name, in: machOFile, outputDirectory: outputDirectory)
    }

    private static func dispatchSuite(_ name: String, in machOFile: MachOFile, outputDirectory: URL) throws {
        switch name {
        // Anonymous/
        case "AnonymousContext":
            try AnonymousContextBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "AnonymousContextDescriptor":
            try AnonymousContextDescriptorBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "AnonymousContextDescriptorFlags":
            try AnonymousContextDescriptorFlagsBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "AnonymousContextDescriptorProtocol":
            try AnonymousContextDescriptorProtocolBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        // ContextDescriptor/
        case "ContextDescriptor":
            try ContextDescriptorBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "ContextDescriptorFlags":
            try ContextDescriptorFlagsBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "ContextDescriptorKind":
            try ContextDescriptorKindBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "ContextDescriptorKindSpecificFlags":
            try ContextDescriptorKindSpecificFlagsBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "ContextDescriptorProtocol":
            try ContextDescriptorProtocolBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "ContextDescriptorWrapper":
            try ContextDescriptorWrapperBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "ContextProtocol":
            try ContextProtocolBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "ContextWrapper":
            try ContextWrapperBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "NamedContextDescriptorProtocol":
            try NamedContextDescriptorProtocolBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        // Extension/
        case "ExtensionContext":
            try ExtensionContextBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "ExtensionContextDescriptor":
            try ExtensionContextDescriptorBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "ExtensionContextDescriptorProtocol":
            try ExtensionContextDescriptorProtocolBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        // Module/
        case "ModuleContext":
            try ModuleContextBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "ModuleContextDescriptor":
            try ModuleContextDescriptorBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        // Type/Struct/
        case "StructDescriptor":
            try StructDescriptorBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "Struct":
            try StructBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "StructMetadata":
            try StructMetadataBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "StructMetadataProtocol":
            try StructMetadataProtocolBaselineGenerator.generate(outputDirectory: outputDirectory)
        // Type/Class/
        case "AnyClassMetadata":
            try AnyClassMetadataBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "AnyClassMetadataObjCInterop":
            try AnyClassMetadataObjCInteropBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "AnyClassMetadataObjCInteropProtocol":
            try AnyClassMetadataObjCInteropProtocolBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "AnyClassMetadataProtocol":
            try AnyClassMetadataProtocolBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "Class":
            try ClassBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "ClassDescriptor":
            try ClassDescriptorBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "ClassFlags":
            try ClassFlagsBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "ClassMetadata":
            try ClassMetadataBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "ClassMetadataBounds":
            try ClassMetadataBoundsBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "ClassMetadataBoundsProtocol":
            try ClassMetadataBoundsProtocolBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "ClassMetadataObjCInterop":
            try ClassMetadataObjCInteropBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "ExtraClassDescriptorFlags":
            try ExtraClassDescriptorFlagsBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "FinalClassMetadataProtocol":
            try FinalClassMetadataProtocolBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "MethodDefaultOverrideDescriptor":
            try MethodDefaultOverrideDescriptorBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "MethodDefaultOverrideTableHeader":
            try MethodDefaultOverrideTableHeaderBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "MethodDescriptor":
            try MethodDescriptorBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "MethodDescriptorFlags":
            try MethodDescriptorFlagsBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "MethodDescriptorKind":
            try MethodDescriptorKindBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "MethodOverrideDescriptor":
            try MethodOverrideDescriptorBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "ObjCClassWrapperMetadata":
            try ObjCClassWrapperMetadataBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "ObjCResilientClassStubInfo":
            try ObjCResilientClassStubInfoBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "OverrideTableHeader":
            try OverrideTableHeaderBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "ResilientSuperclass":
            try ResilientSuperclassBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "StoredClassMetadataBounds":
            try StoredClassMetadataBoundsBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "VTableDescriptorHeader":
            try VTableDescriptorHeaderBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        // Type/Enum/
        case "Enum":
            try EnumBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "EnumDescriptor":
            try EnumDescriptorBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "EnumFunctions":
            try EnumFunctionsBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "EnumMetadata":
            try EnumMetadataBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "EnumMetadataProtocol":
            try EnumMetadataProtocolBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "MultiPayloadEnumDescriptor":
            try MultiPayloadEnumDescriptorBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        // Type/ root
        case "TypeContextDescriptor":
            try TypeContextDescriptorBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "TypeContextDescriptorFlags":
            try TypeContextDescriptorFlagsBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "TypeContextDescriptorProtocol":
            try TypeContextDescriptorProtocolBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "TypeContextDescriptorWrapper":
            try TypeContextDescriptorWrapperBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "TypeContextWrapper":
            try TypeContextWrapperBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "TypeMetadataRecord":
            try TypeMetadataRecordBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "TypeReference":
            try TypeReferenceBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "ValueMetadata":
            try ValueMetadataBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "ValueMetadataProtocol":
            try ValueMetadataProtocolBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "ValueTypeDescriptorWrapper":
            try ValueTypeDescriptorWrapperBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        // Protocol/
        case "InvertibleProtocolSet":
            try InvertibleProtocolSetBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "InvertibleProtocolsRequirementCount":
            try InvertibleProtocolsRequirementCountBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "ObjCProtocolPrefix":
            try ObjCProtocolPrefixBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "Protocol":
            try ProtocolBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "ProtocolBaseRequirement":
            try ProtocolBaseRequirementBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "ProtocolContextDescriptorFlags":
            try ProtocolContextDescriptorFlagsBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "ProtocolDescriptor":
            try ProtocolDescriptorBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "ProtocolDescriptorFlags":
            try ProtocolDescriptorFlagsBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "ProtocolDescriptorRef":
            try ProtocolDescriptorRefBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "ProtocolRecord":
            try ProtocolRecordBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "ProtocolRequirement":
            try ProtocolRequirementBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "ProtocolRequirementFlags":
            try ProtocolRequirementFlagsBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "ProtocolRequirementKind":
            try ProtocolRequirementKindBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "ProtocolWitnessTable":
            try ProtocolWitnessTableBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "RelativeObjCProtocolPrefix":
            try RelativeObjCProtocolPrefixBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "ResilientWitness":
            try ResilientWitnessBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "ResilientWitnessesHeader":
            try ResilientWitnessesHeaderBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        // ProtocolConformance/
        case "GlobalActorReference":
            try GlobalActorReferenceBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "ProtocolConformance":
            try ProtocolConformanceBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "ProtocolConformanceDescriptor":
            try ProtocolConformanceDescriptorBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "ProtocolConformanceFlags":
            try ProtocolConformanceFlagsBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        // Generic/
        case "GenericContext":
            try GenericContextBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "GenericContextDescriptorFlags":
            try GenericContextDescriptorFlagsBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "GenericContextDescriptorHeader":
            try GenericContextDescriptorHeaderBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "GenericEnvironment":
            try GenericEnvironmentBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "GenericEnvironmentFlags":
            try GenericEnvironmentFlagsBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "GenericPackShapeDescriptor":
            try GenericPackShapeDescriptorBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "GenericPackShapeHeader":
            try GenericPackShapeHeaderBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "GenericParamDescriptor":
            try GenericParamDescriptorBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "GenericRequirement":
            try GenericRequirementBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "GenericRequirementContent":
            try GenericRequirementContentBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "GenericRequirementDescriptor":
            try GenericRequirementDescriptorBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "GenericRequirementFlags":
            try GenericRequirementFlagsBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "GenericValueDescriptor":
            try GenericValueDescriptorBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "GenericValueHeader":
            try GenericValueHeaderBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "GenericWitnessTable":
            try GenericWitnessTableBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "TypeGenericContextDescriptorHeader":
            try TypeGenericContextDescriptorHeaderBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        // FieldDescriptor/
        case "FieldDescriptor":
            try FieldDescriptorBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        // FieldRecord/
        case "FieldRecord":
            try FieldRecordBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "FieldRecordFlags":
            try FieldRecordFlagsBaselineGenerator.generate(outputDirectory: outputDirectory)
        // AssociatedType/
        case "AssociatedType":
            try AssociatedTypeBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "AssociatedTypeDescriptor":
            try AssociatedTypeDescriptorBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "AssociatedTypeRecord":
            try AssociatedTypeRecordBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        // Metadata/
        case "CanonicalSpecializedMetadataAccessorsListEntry":
            try CanonicalSpecializedMetadataAccessorsListEntryBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "CanonicalSpecializedMetadatasCachingOnceToken":
            try CanonicalSpecializedMetadatasCachingOnceTokenBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "CanonicalSpecializedMetadatasListCount":
            try CanonicalSpecializedMetadatasListCountBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "CanonicalSpecializedMetadatasListEntry":
            try CanonicalSpecializedMetadatasListEntryBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "FixedArrayTypeMetadata":
            try FixedArrayTypeMetadataBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "FullMetadata":
            try FullMetadataBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "Metadata":
            try MetadataBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "MetadataAccessorFunction":
            try MetadataAccessorFunctionBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "MetadataBounds":
            try MetadataBoundsBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "MetadataBoundsProtocol":
            try MetadataBoundsProtocolBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "MetadataProtocol":
            try MetadataProtocolBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "MetadataRequest":
            try MetadataRequestBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "MetadataResponse":
            try MetadataResponseBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "MetadataWrapper":
            try MetadataWrapperBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "MetatypeMetadata":
            try MetatypeMetadataBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "SingletonMetadataPointer":
            try SingletonMetadataPointerBaselineGenerator.generate(outputDirectory: outputDirectory)
        // Metadata/Headers/
        case "HeapMetadataHeader":
            try HeapMetadataHeaderBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "HeapMetadataHeaderPrefix":
            try HeapMetadataHeaderPrefixBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "TypeMetadataHeader":
            try TypeMetadataHeaderBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "TypeMetadataHeaderBase":
            try TypeMetadataHeaderBaseBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "TypeMetadataLayoutPrefix":
            try TypeMetadataLayoutPrefixBaselineGenerator.generate(outputDirectory: outputDirectory)
        // Metadata/MetadataInitialization/
        case "ForeignMetadataInitialization":
            try ForeignMetadataInitializationBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "SingletonMetadataInitialization":
            try SingletonMetadataInitializationBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        // BuiltinType/
        case "BuiltinType":
            try BuiltinTypeBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        case "BuiltinTypeDescriptor":
            try BuiltinTypeDescriptorBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        // DispatchClass/
        case "DispatchClassMetadata":
            try DispatchClassMetadataBaselineGenerator.generate(outputDirectory: outputDirectory)
        // ExistentialType/
        case "ExistentialMetatypeMetadata":
            try ExistentialMetatypeMetadataBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "ExistentialTypeFlags":
            try ExistentialTypeFlagsBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "ExistentialTypeMetadata":
            try ExistentialTypeMetadataBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "ExtendedExistentialTypeMetadata":
            if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
                try ExtendedExistentialTypeMetadataBaselineGenerator.generate(outputDirectory: outputDirectory)
            }
        case "ExtendedExistentialTypeShape":
            if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
                try ExtendedExistentialTypeShapeBaselineGenerator.generate(outputDirectory: outputDirectory)
            }
        case "ExtendedExistentialTypeShapeFlags":
            if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
                try ExtendedExistentialTypeShapeFlagsBaselineGenerator.generate(outputDirectory: outputDirectory)
            }
        case "NonUniqueExtendedExistentialTypeShape":
            try NonUniqueExtendedExistentialTypeShapeBaselineGenerator.generate(outputDirectory: outputDirectory)
        // ForeignType/
        case "ForeignClassMetadata":
            try ForeignClassMetadataBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "ForeignReferenceTypeMetadata":
            try ForeignReferenceTypeMetadataBaselineGenerator.generate(outputDirectory: outputDirectory)
        // Function/
        case "FunctionTypeFlags":
            try FunctionTypeFlagsBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "FunctionTypeMetadata":
            try FunctionTypeMetadataBaselineGenerator.generate(outputDirectory: outputDirectory)
        // Heap/
        case "GenericBoxHeapMetadata":
            try GenericBoxHeapMetadataBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "HeapLocalVariableMetadata":
            try HeapLocalVariableMetadataBaselineGenerator.generate(outputDirectory: outputDirectory)
        // Mangling/
        case "MangledName":
            try MangledNameBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        // OpaqueType/
        case "OpaqueMetadata":
            try OpaqueMetadataBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "OpaqueType":
            try OpaqueTypeBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "OpaqueTypeDescriptor":
            try OpaqueTypeDescriptorBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "OpaqueTypeDescriptorProtocol":
            try OpaqueTypeDescriptorProtocolBaselineGenerator.generate(outputDirectory: outputDirectory)
        // TupleType/
        case "TupleTypeMetadata":
            try TupleTypeMetadataBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "TupleTypeMetadataElement":
            try TupleTypeMetadataElementBaselineGenerator.generate(outputDirectory: outputDirectory)
        // ValueWitnessTable/
        case "TypeLayout":
            try TypeLayoutBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "ValueWitnessFlags":
            try ValueWitnessFlagsBaselineGenerator.generate(outputDirectory: outputDirectory)
        case "ValueWitnessTable":
            try ValueWitnessTableBaselineGenerator.generate(outputDirectory: outputDirectory)
        default:
            throw BaselineGeneratorError.unknownSuite(name)
        }
    }

    private static func loadFixtureMachOFile() throws -> MachOFile {
        let file = try loadFromFile(named: .SymbolTestsCore)
        switch file {
        case .fat(let fat):
            return try required(
                fat.machOFiles().first(where: { $0.header.cpuType == .arm64 })
                    ?? fat.machOFiles().first
            )
        case .machO(let machO):
            return machO
        @unknown default:
            fatalError()
        }
    }

    /// Hand-maintained index of every Suite type registered in `dispatchSuite`.
    /// Emits `__Baseline__/AllFixtureSuites.swift`, which the Coverage Invariant
    /// Test (Task 16) reads as `[any FixtureSuite.Type]`.
    ///
    /// When adding a new Suite, append its type name (the class name, NOT the
    /// `testedTypeName` String) to `suiteTypeNames`. The list is sorted at emit
    /// time, so order here doesn't matter — keep it stable for code review.
    ///
    /// Note: `OpaqueTypeFixtureTests` covers `OpaqueType` (the file is named
    /// `OpaqueTypeFixtureTests.swift` to avoid collision with the
    /// `OpaqueTypeTests` SnapshotInterfaceTests Suite that lives in the same
    /// target). The Coverage Invariant test keys by `testedTypeName`, so the
    /// class-name suffix is irrelevant for coverage purposes.
    private static func writeAllFixtureSuitesIndex(outputDirectory: URL) throws {
        let suiteTypeNames = [
            "AnonymousContextDescriptorFlagsTests",
            "AnonymousContextDescriptorProtocolTests",
            "AnonymousContextDescriptorTests",
            "AnonymousContextTests",
            "AnyClassMetadataObjCInteropProtocolTests",
            "AnyClassMetadataObjCInteropTests",
            "AnyClassMetadataProtocolTests",
            "AnyClassMetadataTests",
            "AssociatedTypeDescriptorTests",
            "AssociatedTypeRecordTests",
            "AssociatedTypeTests",
            "BuiltinTypeDescriptorTests",
            "BuiltinTypeTests",
            "CanonicalSpecializedMetadataAccessorsListEntryTests",
            "CanonicalSpecializedMetadatasCachingOnceTokenTests",
            "CanonicalSpecializedMetadatasListCountTests",
            "CanonicalSpecializedMetadatasListEntryTests",
            "ClassDescriptorTests",
            "ClassFlagsTests",
            "ClassMetadataBoundsProtocolTests",
            "ClassMetadataBoundsTests",
            "ClassMetadataObjCInteropTests",
            "ClassMetadataTests",
            "ClassTests",
            "ContextDescriptorFlagsTests",
            "ContextDescriptorKindSpecificFlagsTests",
            "ContextDescriptorKindTests",
            "ContextDescriptorProtocolTests",
            "ContextDescriptorTests",
            "ContextDescriptorWrapperTests",
            "ContextProtocolTests",
            "ContextWrapperTests",
            "DispatchClassMetadataTests",
            "EnumDescriptorTests",
            "EnumFunctionsTests",
            "EnumMetadataProtocolTests",
            "EnumMetadataTests",
            "EnumTests",
            "ExistentialMetatypeMetadataTests",
            "ExistentialTypeFlagsTests",
            "ExistentialTypeMetadataTests",
            "ExtendedExistentialTypeMetadataTests",
            "ExtendedExistentialTypeShapeFlagsTests",
            "ExtendedExistentialTypeShapeTests",
            "ExtensionContextDescriptorProtocolTests",
            "ExtensionContextDescriptorTests",
            "ExtensionContextTests",
            "ExtraClassDescriptorFlagsTests",
            "FieldDescriptorTests",
            "FieldRecordFlagsTests",
            "FieldRecordTests",
            "FinalClassMetadataProtocolTests",
            "FixedArrayTypeMetadataTests",
            "ForeignClassMetadataTests",
            "ForeignMetadataInitializationTests",
            "ForeignReferenceTypeMetadataTests",
            "FullMetadataTests",
            "FunctionTypeFlagsTests",
            "FunctionTypeMetadataTests",
            "GenericBoxHeapMetadataTests",
            "GenericContextDescriptorFlagsTests",
            "GenericContextDescriptorHeaderTests",
            "GenericContextTests",
            "GenericEnvironmentFlagsTests",
            "GenericEnvironmentTests",
            "GenericPackShapeDescriptorTests",
            "GenericPackShapeHeaderTests",
            "GenericParamDescriptorTests",
            "GenericRequirementContentTests",
            "GenericRequirementDescriptorTests",
            "GenericRequirementFlagsTests",
            "GenericRequirementTests",
            "GenericValueDescriptorTests",
            "GenericValueHeaderTests",
            "GenericWitnessTableTests",
            "GlobalActorReferenceTests",
            "HeapLocalVariableMetadataTests",
            "HeapMetadataHeaderPrefixTests",
            "HeapMetadataHeaderTests",
            "InvertibleProtocolSetTests",
            "InvertibleProtocolsRequirementCountTests",
            "MangledNameTests",
            "MetadataAccessorFunctionTests",
            "MetadataBoundsProtocolTests",
            "MetadataBoundsTests",
            "MetadataProtocolTests",
            "MetadataRequestTests",
            "MetadataResponseTests",
            "MetadataTests",
            "MetadataWrapperTests",
            "MetatypeMetadataTests",
            "MethodDefaultOverrideDescriptorTests",
            "MethodDefaultOverrideTableHeaderTests",
            "MethodDescriptorFlagsTests",
            "MethodDescriptorKindTests",
            "MethodDescriptorTests",
            "MethodOverrideDescriptorTests",
            "ModuleContextDescriptorTests",
            "ModuleContextTests",
            "MultiPayloadEnumDescriptorTests",
            "NamedContextDescriptorProtocolTests",
            "NonUniqueExtendedExistentialTypeShapeTests",
            "ObjCClassWrapperMetadataTests",
            "ObjCProtocolPrefixTests",
            "ObjCResilientClassStubInfoTests",
            "OpaqueMetadataTests",
            "OpaqueTypeDescriptorProtocolTests",
            "OpaqueTypeDescriptorTests",
            "OpaqueTypeFixtureTests",
            "OverrideTableHeaderTests",
            "ProtocolBaseRequirementTests",
            "ProtocolConformanceDescriptorTests",
            "ProtocolConformanceFlagsTests",
            "ProtocolConformanceTests",
            "ProtocolContextDescriptorFlagsTests",
            "ProtocolDescriptorFlagsTests",
            "ProtocolDescriptorRefTests",
            "ProtocolDescriptorTests",
            "ProtocolRecordTests",
            "ProtocolRequirementFlagsTests",
            "ProtocolRequirementKindTests",
            "ProtocolRequirementTests",
            "ProtocolTests",
            "ProtocolWitnessTableTests",
            "RelativeObjCProtocolPrefixTests",
            "ResilientSuperclassTests",
            "ResilientWitnessTests",
            "ResilientWitnessesHeaderTests",
            "SingletonMetadataInitializationTests",
            "SingletonMetadataPointerTests",
            "StoredClassMetadataBoundsTests",
            "StructDescriptorTests",
            "StructMetadataProtocolTests",
            "StructMetadataTests",
            "StructTests",
            "TupleTypeMetadataElementTests",
            "TupleTypeMetadataTests",
            "TypeContextDescriptorFlagsTests",
            "TypeContextDescriptorProtocolTests",
            "TypeContextDescriptorTests",
            "TypeContextDescriptorWrapperTests",
            "TypeContextWrapperTests",
            "TypeGenericContextDescriptorHeaderTests",
            "TypeLayoutTests",
            "TypeMetadataHeaderBaseTests",
            "TypeMetadataHeaderTests",
            "TypeMetadataLayoutPrefixTests",
            "TypeMetadataRecordTests",
            "TypeReferenceTests",
            "VTableDescriptorHeaderTests",
            "ValueMetadataProtocolTests",
            "ValueMetadataTests",
            "ValueTypeDescriptorWrapperTests",
            "ValueWitnessFlagsTests",
            "ValueWitnessTableTests",
        ].sorted()

        // Use `\(raw:)` because `\(literal:)` would treat each `Foo.self` as a
        // String literal (i.e. emit `"Foo.self"`).
        let suiteListItems = suiteTypeNames
            .map { "\($0).self" }
            .joined(separator: ",\n    ") + ","

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        @testable import MachOTestingSupport
        import MachOFixtureSupport

        // `FixtureSuite` is `@MainActor`-isolated, so its metatype likewise inherits
        // main-actor isolation. Annotating the constant binds access to MainActor and
        // avoids the Sendable diagnostic on this global.
        @MainActor
        """

        let file: SourceFileSyntax = """
        \(raw: header)
        let allFixtureSuites: [any FixtureSuite.Type] = [
            \(raw: suiteListItems)
        ]
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("AllFixtureSuites.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}

package enum BaselineGeneratorError: Error, CustomStringConvertible {
    case unknownSuite(String)

    package var description: String {
        switch self {
        case .unknownSuite(let name):
            return "Unknown suite: \(name). Use --help for the list of valid suites."
        }
    }
}
