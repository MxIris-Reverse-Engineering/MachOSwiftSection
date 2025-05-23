import Foundation
import MachOKit

public struct ProtocolConformanceDescriptor: LocatableLayoutWrapper {
    public struct Layout {
        public let protocolDescriptor: RelativeContextPointer<ProtocolDescriptor?>
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
    public func protocolDescriptor(in machOFile: MachOFile) throws -> ResolvableElement<ProtocolDescriptor>? {
        try layout.protocolDescriptor.resolve(from: fileOffset(of: \.protocolDescriptor), in: machOFile).asOptional
    }

    public var typeReference: TypeReference {
        return .forKind(layout.flags.typeReferenceKind, at: layout.typeReference)
    }

    public func resolvedTypeReference(in machOFile: MachOFile) throws -> ResolvedTypeReference {
        let fileOffset = fileOffset(of: \.typeReference)
        return try typeReference.resolve(at: fileOffset, in: machOFile)
    }

    public func witnessTablePattern(in machOFile: MachOFile) throws -> ProtocolWitnessTable? {
        try layout.witnessTablePattern.resolve(from: fileOffset(of: \.witnessTablePattern), in: machOFile)
    }
}
