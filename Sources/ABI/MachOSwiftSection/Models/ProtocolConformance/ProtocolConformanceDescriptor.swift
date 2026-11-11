import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct ProtocolConformanceDescriptor {
    public struct Layout: LayoutProtocol {
        public let protocolDescriptor: RelativeSymbolOrElementPointer<ProtocolDescriptor?>
        public let typeReference: RelativeOffset
        public let witnessTablePattern: RelativeDirectPointer<ProtocolWitnessTable>
        public let flags: ProtocolConformanceFlags
    }
}

extension ProtocolConformanceDescriptor {
    /// The conforming type. A reference kind this reader does not know stops
    /// the program, as it always has: `TypeReference` has no case to hold it.
    public var typeReference: TypeReference {
        guard let typeReferenceKind = layout.flags.typeReferenceKind else {
            preconditionFailure("conformance flags 0x\(String(layout.flags.rawValue, radix: 16)) name a type reference kind this reader does not know")
        }
        return .forKind(typeReferenceKind, at: layout.typeReference)
    }
}

// MARK: - ReadingContext Support

extension ProtocolConformanceDescriptor {
    public func protocolDescriptor(in context: some ReadingContext) throws -> SymbolOrElement<ProtocolDescriptor>? {
        try layout.protocolDescriptor.resolve(at: try context.addressFromOffset(offset(of: \.protocolDescriptor)), in: context).asOptional
    }

    public func resolvedTypeReference(in context: some ReadingContext) throws -> ResolvedTypeReference {
        return try typeReference.resolve(at: offset(of: \.typeReference), in: context)
    }

    public func witnessTablePattern(in context: some ReadingContext) throws -> ProtocolWitnessTable? {
        try layout.witnessTablePattern.resolve(at: try context.addressFromOffset(offset(of: \.witnessTablePattern)), in: context)
    }
}
