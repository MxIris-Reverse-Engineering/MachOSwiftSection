import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
@testable import SwiftLayout
import Demangling

/// Shared helpers for the SwiftLayout fixture suites. Factored out of
/// `DependencyClosureLayoutTests` so the dependency-closure and ObjC-ancestor
/// suites compute and assert field offsets the same way (single source). None
/// of them touch suite state, so they are free functions rather than a base
/// class.

/// Finds a struct/class type in `machO` by its fully-qualified name and returns
/// the statically-computed field layout for it.
func fieldLayout<MachO: MachOSwiftSectionRepresentableWithCache>(
    ofQualifiedTypeName qualifiedTypeName: String,
    with calculator: StaticLayoutCalculator<MachO>,
    in machO: MachO,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> AggregateFieldLayout {
    for contextDescriptor in try machO.swift.contextDescriptors {
        guard let descriptor = contextDescriptor.typeContextDescriptorWrapper else { continue }
        guard descriptor.isStruct || descriptor.isClass else { continue }
        guard
            let name = (try? MetadataReader.demangleContext(for: contextDescriptor, in: machO))
                .flatMap(NodeTypeNaming.nominalQualifiedName(of:)),
            name == qualifiedTypeName
        else { continue }
        return try calculator.fieldLayout(of: descriptor)
    }
    Issue.record("type \(qualifiedTypeName) not found in fixture", sourceLocation: sourceLocation)
    throw LayoutResolutionError.unknown(.typeDescriptorNotFound(qualifiedTypeName: qualifiedTypeName))
}

/// Finds a *generic* struct/class type in `machO` by its fully-qualified
/// (generic-argument-free) name and returns the statically-computed field
/// layout for a concrete instantiation, substituting the depth-0 parameters
/// with `genericArguments` (`.type`-wrapped type nodes, declaration order).
func fieldLayout<MachO: MachOSwiftSectionRepresentableWithCache>(
    ofGenericQualifiedTypeName qualifiedTypeName: String,
    genericArguments: [Node],
    with calculator: StaticLayoutCalculator<MachO>,
    in machO: MachO,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> AggregateFieldLayout {
    for contextDescriptor in try machO.swift.contextDescriptors {
        guard let descriptor = contextDescriptor.typeContextDescriptorWrapper else { continue }
        guard descriptor.isStruct || descriptor.isClass else { continue }
        guard
            let name = (try? MetadataReader.demangleContext(for: contextDescriptor, in: machO))
                .flatMap(NodeTypeNaming.nominalQualifiedName(of:)),
            name == qualifiedTypeName
        else { continue }
        return try calculator.fieldLayout(of: descriptor, genericArguments: genericArguments)
    }
    Issue.record("generic type \(qualifiedTypeName) not found in fixture", sourceLocation: sourceLocation)
    throw LayoutResolutionError.unknown(.typeDescriptorNotFound(qualifiedTypeName: qualifiedTypeName))
}

/// The runtime field-offset vector of a concrete generic instantiation,
/// obtained by materializing its *specialized* metadata through the accessor
/// with `argumentMetatype` as the single depth-0 generic argument (no protocol
/// witness tables — the helper covers requirement-free generics only). This is
/// the independent ground truth the top-level static instantiation path is
/// checked against. `nil` for types with no field-offset vector.
func runtimeFieldOffsets(
    ofGenericQualifiedTypeName qualifiedTypeName: String,
    argumentMetatype: Any.Type,
    in machO: MachOImage
) throws -> [Int]? {
    for contextDescriptor in try machO.swift.contextDescriptors {
        guard let descriptor = contextDescriptor.typeContextDescriptorWrapper else { continue }
        guard
            let name = (try? MetadataReader.demangleContext(for: contextDescriptor, in: machO))
                .flatMap(NodeTypeNaming.nominalQualifiedName(of:)),
            name == qualifiedTypeName,
            let accessor = try descriptor.typeContextDescriptor.metadataAccessorFunction(in: machO)
        else { continue }
        let response = try accessor(request: .init(), metatypes: argumentMetatype)
        let metadata = try response.value.resolve(in: machO)
        switch metadata {
        case .struct(let structMetadata):
            return try structMetadata.fieldOffsets(in: machO).map { Int($0) }
        case .class(let classMetadata):
            return try classMetadata.fieldOffsets(in: machO).map { Int($0) }
        default:
            return nil
        }
    }
    return nil
}

/// The runtime field-offset vector of a type, obtained by materializing its
/// metadata through the accessor — the independent ground truth a static
/// computation is checked against. `nil` for types with no field-offset vector.
func runtimeFieldOffsets(ofQualifiedTypeName qualifiedTypeName: String, in machO: MachOImage) throws -> [Int]? {
    for contextDescriptor in try machO.swift.contextDescriptors {
        guard let descriptor = contextDescriptor.typeContextDescriptorWrapper else { continue }
        guard
            let name = (try? MetadataReader.demangleContext(for: contextDescriptor, in: machO))
                .flatMap(NodeTypeNaming.nominalQualifiedName(of:)),
            name == qualifiedTypeName,
            let accessor = try descriptor.typeContextDescriptor.metadataAccessorFunction(in: machO)
        else { continue }
        let response = try accessor(request: .init())
        let metadata = try response.value.resolve(in: machO)
        switch metadata {
        case .struct(let structMetadata):
            return try structMetadata.fieldOffsets(in: machO).map { Int($0) }
        case .class(let classMetadata):
            return try classMetadata.fieldOffsets(in: machO).map { Int($0) }
        default:
            return nil
        }
    }
    return nil
}

/// The runtime whole-type (size, stride) of a type, read from its value-witness
/// table after materializing the metadata via the accessor — the ground truth a
/// builtin-descriptor-backed static layout (multi-payload enums, imported C
/// value types) is checked against. `nil` if the type is not found.
func runtimeValueWitnessSizeStride(ofQualifiedTypeName qualifiedTypeName: String, in machO: MachOImage) throws -> (size: Int, stride: Int)? {
    for contextDescriptor in try machO.swift.contextDescriptors {
        guard let descriptor = contextDescriptor.typeContextDescriptorWrapper else { continue }
        guard
            let name = (try? MetadataReader.demangleContext(for: contextDescriptor, in: machO))
                .flatMap(NodeTypeNaming.nominalQualifiedName(of:)),
            name == qualifiedTypeName,
            let accessor = try descriptor.typeContextDescriptor.metadataAccessorFunction(in: machO)
        else { continue }
        let response = try accessor(request: .init())
        let metadata = try response.value.resolve(in: machO)
        let valueWitnessTable = try metadata.valueWitnessTable(in: machO)
        return (Int(valueWitnessTable.layout.size), Int(valueWitnessTable.layout.stride))
    }
    return nil
}

/// Asserts every field resolved (none degraded to `unknown`) and the computed
/// offset vector matches `expectedOffsets` exactly.
func assertFullyComputed(
    _ aggregate: AggregateFieldLayout,
    equals expectedOffsets: [Int],
    typeName: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let unresolved = aggregate.fields.compactMap { field -> String? in
        if case .unknown(let reason) = field.resolution { return "\(field.fieldName):\(reason)" }
        return nil
    }
    #expect(unresolved.isEmpty, "\(typeName) has unresolved fields: \(unresolved)", sourceLocation: sourceLocation)
    #expect(
        aggregate.computedFieldOffsets == expectedOffsets,
        "\(typeName): computed \(aggregate.computedFieldOffsets) != expected \(expectedOffsets)",
        sourceLocation: sourceLocation
    )
}
