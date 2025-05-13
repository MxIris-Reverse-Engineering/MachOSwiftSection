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
    
    func typeOrProtocolOrConformanceOrLayoutOrInvertedProtocols(in machO: MachOFile) -> GenericRequirementTypeOrProtocolOrConformanceOrLayoutOrInvertedProtocols {
        switch layout.flags.kind {
        case .protocol:
            let ptr = RelativeIndirectableRawPointerIntPair<Bool>(relativeOffsetPlusIndirectAndInt: layout.typeOrProtocolOrConformanceOrLayoutOffset)
            if ptr.value {
                return .protocol(.objcPointer(.init(relativeOffsetPlusIndirectAndInt: layout.typeOrProtocolOrConformanceOrLayoutOffset)))
            } else {
                return .protocol(.swiftPointer(.init(relativeOffsetPlusIndirectAndInt: layout.typeOrProtocolOrConformanceOrLayoutOffset)))
            }
        case .sameType, .baseClass, .sameShape:
            return .type(.init(relativeOffset: layout.typeOrProtocolOrConformanceOrLayoutOffset))
        case .sameConformance:
            return .conformance(.init(relativeOffsetPlusIndirect: layout.typeOrProtocolOrConformanceOrLayoutOffset))
        case .invertedProtocols:
            var value = layout.typeOrProtocolOrConformanceOrLayoutOffset
            return .invertedProtocols(withUnsafeBytes(of: &value, {
                $0.baseAddress!.load(as: GenericRequirementTypeOrProtocolOrConformanceOrLayoutOrInvertedProtocols.InvertedProtocols.self)
            }))
        case .layout:
            return .layout(.init(rawValue: layout.typeOrProtocolOrConformanceOrLayoutOffset.cast())!)
        }
    }
}

public enum GenericRequirementTypeOrProtocolOrConformanceOrLayoutOrInvertedProtocols {
    case type(RelativeDirectPointer<MangledName>)
    case `protocol`(RelativeProtocolDescriptorPointer)
    case layout(GenericRequirementLayoutKind)
    case conformance(RelativeIndirectablePointer<ProtocolConformanceDescriptor, Pointer<ProtocolConformanceDescriptor>>)
    case invertedProtocols(InvertedProtocols)
    public struct InvertedProtocols {
        let genericParamIndex: UInt16
        let protocols: InvertibleProtocolSet
    }
}




