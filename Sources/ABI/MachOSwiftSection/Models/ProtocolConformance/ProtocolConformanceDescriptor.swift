import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct ProtocolConformanceDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let protocolDescriptor: RelativeSymbolOrElementPointer<ProtocolDescriptor?>
        public let typeReference: RelativeOffset
        public let witnessTablePattern: RelativeDirectPointer<ProtocolWitnessTable>
        public let flags: ProtocolConformanceFlags
    }
}

extension ProtocolConformanceDescriptor {
    public var typeReference: TypeReference {
        return .forKind(layout.flags.typeReferenceKind, at: layout.typeReference)
    }
}

extension ProtocolConformanceDescriptor {
    public func protocolDescriptor(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> SymbolOrElement<ProtocolDescriptor>? {
        try layout.protocolDescriptor.resolve(from: offset(of: \.protocolDescriptor), in: machO).asOptional
    }

    public func resolvedTypeReference(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ResolvedTypeReference {
        let offset = offset(of: \.typeReference)
        return try typeReference.resolve(at: offset, in: machO)
    }

    public func witnessTablePattern(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ProtocolWitnessTable? {
        try layout.witnessTablePattern.resolve(from: offset(of: \.witnessTablePattern), in: machO)
    }
}

extension ProtocolConformanceDescriptor {
    public func protocolDescriptor() throws -> SymbolOrElement<ProtocolDescriptor>? {
        try layout.protocolDescriptor.resolve(from: pointer(of: \.protocolDescriptor)).asOptional
    }

    public func resolvedTypeReference() throws -> ResolvedTypeReference {
        return try typeReference.resolve(from: pointer(of: \.typeReference))
    }

    public func witnessTablePattern() throws -> ProtocolWitnessTable? {
        try layout.witnessTablePattern.resolve(from: pointer(of: \.witnessTablePattern))
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
