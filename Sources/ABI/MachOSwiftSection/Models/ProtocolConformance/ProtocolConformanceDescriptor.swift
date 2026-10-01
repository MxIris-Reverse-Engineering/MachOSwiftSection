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

// MARK: - Deprecated Mach-O and pointer forms

extension ProtocolConformanceDescriptor {
    @available(*, deprecated, message: "Pass a ReadingContext: protocolDescriptor(in: machO.context).")
    public func protocolDescriptor(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> SymbolOrElement<ProtocolDescriptor>? {
        try protocolDescriptor(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolvedTypeReference(in: machO.context).")
    public func resolvedTypeReference(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ResolvedTypeReference {
        try resolvedTypeReference(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: witnessTablePattern(in: machO.context).")
    public func witnessTablePattern(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ProtocolWitnessTable? {
        try witnessTablePattern(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: protocolDescriptor(in: .inProcess).")
    public func protocolDescriptor() throws -> SymbolOrElement<ProtocolDescriptor>? {
        try protocolDescriptor(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolvedTypeReference(in: .inProcess).")
    public func resolvedTypeReference() throws -> ResolvedTypeReference {
        try resolvedTypeReference(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: witnessTablePattern(in: .inProcess).")
    public func witnessTablePattern() throws -> ProtocolWitnessTable? {
        try witnessTablePattern(in: InProcessContext.shared)
    }
}
