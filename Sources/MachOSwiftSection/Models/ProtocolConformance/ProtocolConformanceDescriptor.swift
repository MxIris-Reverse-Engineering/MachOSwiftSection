import Foundation
import MachOKit
import MachOSwiftSectionMacro

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

@MachOImageAllMembersGenerator
extension ProtocolConformanceDescriptor {
    public func protocolDescriptor(in machOFile: MachOFile) throws -> ResolvableElement<ProtocolDescriptor>? {
        try layout.protocolDescriptor.resolve(from: offset(of: \.protocolDescriptor), in: machOFile).asOptional
    }

    public var typeReference: TypeReference {
        return .forKind(layout.flags.typeReferenceKind, at: layout.typeReference)
    }

    public func resolvedTypeReference(in machOFile: MachOFile) throws -> ResolvedTypeReference {
        let offset = offset(of: \.typeReference)
        return try typeReference.resolve(at: offset, in: machOFile)
    }

    public func witnessTablePattern(in machOFile: MachOFile) throws -> ProtocolWitnessTable? {
        try layout.witnessTablePattern.resolve(from: offset(of: \.witnessTablePattern), in: machOFile)
    }
}
