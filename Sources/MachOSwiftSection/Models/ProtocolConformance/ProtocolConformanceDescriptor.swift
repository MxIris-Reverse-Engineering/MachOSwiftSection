import Foundation
import MachOKit
import MachOFoundation

public struct ProtocolConformanceDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let protocolDescriptor: RelativeSymbolOrElementPointer<ProtocolDescriptor?>
        public let typeReference: RelativeOffset
        public let witnessTablePattern: RelativeDirectPointer<ProtocolWitnessTable>
        public let flags: ProtocolConformanceFlags
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension ProtocolConformanceDescriptor {
    public var typeReference: TypeReference {
        return .forKind(layout.flags.typeReferenceKind, at: layout.typeReference)
    }
}

extension ProtocolConformanceDescriptor {
    public func protocolDescriptor<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> SymbolOrElement<ProtocolDescriptor>? {
        try layout.protocolDescriptor.resolve(from: offset(of: \.protocolDescriptor), in: machO).asOptional
    }

    public func resolvedTypeReference<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> ResolvedTypeReference {
        let offset = offset(of: \.typeReference)
        return try typeReference.resolve(at: offset, in: machO)
    }

    public func witnessTablePattern<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> ProtocolWitnessTable? {
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
