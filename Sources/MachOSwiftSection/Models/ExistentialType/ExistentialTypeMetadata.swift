import Foundation
import MachOKit
import MachOFoundation

public struct ExistentialTypeMetadata: MetadataProtocol {
    public struct Layout: ExistentialTypeMetadataLayout {
        public let kind: StoredPointer
        public let flags: ExistentialTypeFlags
        public let numberOfProtocols: UInt32
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
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

extension ExistentialTypeMetadata {
    public func superclassConstraint(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ConstMetadataPointer<Metadata>? {
        guard layout.flags.hasSuperclassConstraint else { return nil }
        return try .resolve(from: offset + layoutSize, in: machO)
    }
    
    public func protocols(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> [ProtocolDescriptorRef] {
        guard layout.numberOfProtocols != .zero else { return [] }
        var offset = offset + layoutSize
        if layout.flags.hasSuperclassConstraint {
            offset.offset(of: ConstMetadataPointer<Metadata>.self)
        }
        return try machO.readElements(offset: offset, numberOfElements: layout.numberOfProtocols.cast())
    }
}

extension ExistentialTypeMetadata {
    public func superclassConstraint() throws -> ConstMetadataPointer<Metadata>? {
        guard layout.flags.hasSuperclassConstraint else { return nil }
        return try .resolve(from: .init(bitPattern: offset + layoutSize))
    }
    
    public func protocols() throws -> [ProtocolDescriptorRef] {
        guard layout.numberOfProtocols != .zero else { return [] }
        var offset = layoutSize
        if layout.flags.hasSuperclassConstraint {
            offset.offset(of: ConstMetadataPointer<Metadata>.self)
        }
        return try asPointer.readElements(offset: offset, numberOfElements: layout.numberOfProtocols.cast())
    }
}

public enum ExistentialTypeRepresentation {
    case opaque
    case `class`
    case error
}
