import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
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
        switch layout.flags.specialProtocol {
        case .error:
            return .error
        case .none:
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

// MARK: - Deprecated Mach-O and pointer forms

extension ExistentialTypeMetadata {
    @available(*, deprecated, message: "Pass a ReadingContext: superclassConstraint(in: machO.context).")
    public func superclassConstraint(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ConstMetadataPointer<Metadata>? {
        try superclassConstraint(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: protocols(in: machO.context).")
    public func protocols(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> [ProtocolDescriptorRef] {
        try protocols(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: superclassConstraint(in: .inProcess).")
    public func superclassConstraint() throws -> ConstMetadataPointer<Metadata>? {
        try superclassConstraint(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: protocols(in: .inProcess).")
    public func protocols() throws -> [ProtocolDescriptorRef] {
        try protocols(in: InProcessContext.shared)
    }
}
