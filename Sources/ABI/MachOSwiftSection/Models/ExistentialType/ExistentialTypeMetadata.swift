import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct ExistentialTypeMetadata: MetadataProtocol {
    public struct Layout: ExistentialTypeMetadataLayout {
        public let kind: StoredPointer
        public let flags: ExistentialTypeFlags
        public let numberOfProtocols: UInt32
    }
}

extension ExistentialTypeMetadata {
    public var isClassBounded: Bool {
        layout.flags.classConstraint == .class
    }
    
    public var isObjC: Bool {
        isClassBounded && layout.flags.numberOfWitnessTables == 0
    }
    
    public var representation: ExistentialTypeRepresentation {
        // Spelled out: `specialProtocol` is optional and `SpecialProtocolKind`
        // has a `none` case, so a bare `.none` would mean "not read".
        switch layout.flags.specialProtocol {
        case .some(.error):
            return .error
        case .some(.none),
             nil:
            break
        }
        
        if isClassBounded {
            return .class
        }
        
        return .opaque
    }
    
}

public enum ExistentialTypeRepresentation {
    case opaque
    case `class`
    case error
}

// MARK: - ReadingContext Support

extension ExistentialTypeMetadata {
    public func superclassConstraint(in context: some ReadingContext) throws -> ConstMetadataPointer<Metadata>? {
        guard layout.flags.hasSuperclassConstraint else { return nil }
        return try .resolve(at: try context.addressFromOffset(offset + layoutSize), in: context)
    }

    public func protocols(in context: some ReadingContext) throws -> [ProtocolDescriptorRef] {
        guard layout.numberOfProtocols != .zero else { return [] }
        var offset = offset + layoutSize
        if layout.flags.hasSuperclassConstraint {
            offset.offset(of: ConstMetadataPointer<Metadata>.self)
        }
        return try context.readElements(at: try context.addressFromOffset(offset), numberOfElements: layout.numberOfProtocols.cast())
    }
}
