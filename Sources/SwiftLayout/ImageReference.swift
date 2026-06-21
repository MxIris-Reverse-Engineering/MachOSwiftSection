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

    public init(machO: MachO) throws {
        self.machO = machO
        self.builtinLayoutIndex = try BuiltinTypeLayoutIndex(machO: machO)

        var index: [String: TypeContextDescriptorWrapper] = [:]
        for contextDescriptor in try machO.swift.contextDescriptors {
            guard let typeDescriptor = contextDescriptor.typeContextDescriptorWrapper else { continue }
            // `demangleContext` reconstructs the fully-qualified name from the
            // descriptor's parent chain (the descriptor's own `mangledName` is
            // not a demangleable type reference).
            guard
                let contextNode = try? MetadataReader.demangleContext(for: contextDescriptor, in: machO),
                let qualifiedTypeName = NodeTypeNaming.nominalQualifiedName(of: contextNode)
            else { continue }
            index[qualifiedTypeName] = typeDescriptor
        }
        self.typeDescriptorsByQualifiedName = index
    }

    /// Looks up a type descriptor by its fully-qualified name (as produced by
    /// `NodeTypeNaming.nominalQualifiedName`).
    func typeDescriptor(forQualifiedTypeName qualifiedTypeName: String) -> TypeContextDescriptorWrapper? {
        typeDescriptorsByQualifiedName[qualifiedTypeName]
    }
}
