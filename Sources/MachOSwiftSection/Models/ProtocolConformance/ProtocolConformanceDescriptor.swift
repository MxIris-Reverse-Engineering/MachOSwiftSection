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
        let relativeOffset = layout.typeReference
        switch layout.flags.typeReferenceKind {
        case .directTypeDescriptor:
            return .directTypeDescriptor(.init(relativeOffset: relativeOffset))
        case .indirectTypeDescriptor:
            return .indirectTypeDescriptor(.init(relativeOffset: relativeOffset))
        case .directObjCClassName:
            return .directObjCClassName(.init(relativeOffset: relativeOffset))
        case .indirectObjCClass:
            return .indirectObjCClass(.init(relativeOffset: relativeOffset))
        }
    }

    public func resolvedTypeReference(in machOFile: MachOFile) throws -> ResolvedTypeReference {
        let fileOffset = fileOffset(of: \.typeReference)
        switch typeReference {
        case .directTypeDescriptor(let relativeDirectPointer):
            return try .directTypeDescriptor(relativeDirectPointer.resolve(from: fileOffset, in: machOFile))
        case .indirectTypeDescriptor(let relativeIndirectPointer):
            return try .indirectTypeDescriptor(relativeIndirectPointer.resolve(from: fileOffset, in: machOFile).resolve(in: machOFile).asOptional)
        case .directObjCClassName(let relativeDirectPointer):
            return try .directObjCClassName(relativeDirectPointer.resolve(from: fileOffset, in: machOFile))
        case .indirectObjCClass(let relativeIndirectRawPointer):
            // TODO
            return .indirectObjCClass(nil)
        }
    }

    public func witnessTablePattern(in machOFile: MachOFile) throws -> ProtocolWitnessTable? {
        try layout.witnessTablePattern.resolve(from: fileOffset(of: \.witnessTablePattern), in: machOFile)
    }
}
