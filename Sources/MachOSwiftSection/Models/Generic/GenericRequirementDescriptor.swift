//
//  GenericRequirementDescriptor.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/2.
//

import Foundation
import MachOKit

public struct GenericRequirementDescriptor: LocatableLayoutWrapper {
    public struct Layout {
        public let flags: GenericRequirementFlags
        public let param: RelativeDirectPointer<MangledName>
        public let typeOrProtocolOrConformanceOrLayoutOffset: RelativeOffset
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension GenericRequirementDescriptor {
    func paramManagedName(in machO: MachOFile) throws -> MangledName {
        return try layout.param.resolve(from: offset(of: \.param), in: machO)
    }
    
    func type(in machO: MachOFile) throws -> MangledName {
        return try RelativeDirectPointer<MangledName>(relativeOffset: layout.typeOrProtocolOrConformanceOrLayoutOffset).resolve(from: offset(of: \.typeOrProtocolOrConformanceOrLayoutOffset), in: machO)
    }
}

public enum GenericRequirementTypeOrProtocolOrConformanceOrLayoutOrInvertedProtocols {
    case type(RelativeDirectPointer<String>)
    case `protocol`(RelativeProtocolDescriptorPointer)
    case layout(GenericRequirementLayoutKind)
    case conformance(RelativeIndirectablePointer<ProtocolConformanceDescriptor, Pointer<ProtocolConformanceDescriptor>>)
    case invertedProtocols(InvertedProtocols)
    public struct InvertedProtocols {
        let genericParamIndex: UInt16
        let protocols: InvertibleProtocolSet
    }
}




