import Foundation
import MachOExtensions
import MachOFoundation
import MachOKit
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
