import MachOSwiftSection
@_spi(Internals) import SwiftInspection
import Demangling

/// A single Mach-O image plus the per-image indexes the layout engine needs:
/// a fully-qualified-name → type-descriptor map (so a field's demangled type
/// name can be resolved back to its descriptor) and the builtin layout index.
///
/// The resolver carries an `ImageReference` through recursion as "the image
/// the current type is defined in". In the single-image phase there is exactly
/// one; the dependency-closure phase adds more without changing the resolver.
public final class ImageReference<MachO: MachOSwiftSectionRepresentableWithCache>: @unchecked Sendable {
    public let machO: MachO
    let builtinLayoutIndex: BuiltinTypeLayoutIndex
    private let typeDescriptorsByQualifiedName: [String: TypeContextDescriptorWrapper]
    private let protocolClassConstraintsByQualifiedName: [String: ProtocolClassConstraint]

    public init(machO: MachO) throws {
        self.machO = machO
        self.builtinLayoutIndex = try BuiltinTypeLayoutIndex(machO: machO)

        // `demangleContext` reconstructs the fully-qualified name from the
        // descriptor's parent chain (the descriptor's own `mangledName` is not a
        // demangleable type reference).
        var typeIndex: [String: TypeContextDescriptorWrapper] = [:]
        for contextDescriptor in try machO.swift.contextDescriptors {
            guard
                let typeDescriptor = contextDescriptor.typeContextDescriptorWrapper,
                let contextNode = try? MetadataReader.demangleContext(for: contextDescriptor, in: machO),
                let qualifiedTypeName = NodeTypeNaming.nominalQualifiedName(of: contextNode)
            else { continue }
            typeIndex[qualifiedTypeName] = typeDescriptor
        }
        self.typeDescriptorsByQualifiedName = typeIndex

        // Index every Swift protocol's class constraint (from `__swift5_protos`,
        // a separate section from the type context descriptors) so an
        // existential's representation — opaque vs class-bound — can be derived
        // from its protocol composition.
        var protocolIndex: [String: ProtocolClassConstraint] = [:]
        for protocolDescriptor in try machO.swift.protocolDescriptors {
            guard
                let classConstraint = protocolDescriptor.flags.kindSpecificFlags?.protocolFlags?.classConstraint,
                let contextNode = try? MetadataReader.demangleContext(for: .protocol(protocolDescriptor), in: machO),
                let qualifiedTypeName = NodeTypeNaming.declaredQualifiedName(of: contextNode)
            else { continue }
            protocolIndex[qualifiedTypeName] = classConstraint
        }
        self.protocolClassConstraintsByQualifiedName = protocolIndex
    }

    /// Looks up a type descriptor by its fully-qualified name (as produced by
    /// `NodeTypeNaming.nominalQualifiedName`).
    func typeDescriptor(forQualifiedTypeName qualifiedTypeName: String) -> TypeContextDescriptorWrapper? {
        typeDescriptorsByQualifiedName[qualifiedTypeName]
    }

    /// Looks up a Swift protocol's class constraint by its fully-qualified name,
    /// or `nil` if no protocol with that name is defined in this image.
    func protocolClassConstraint(forQualifiedTypeName qualifiedTypeName: String) -> ProtocolClassConstraint? {
        protocolClassConstraintsByQualifiedName[qualifiedTypeName]
    }
}
