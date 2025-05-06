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
        public let param: RelativeDirectPointer<String>
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
    func paramManagedName(in machO: MachOFile) throws -> String {
        return try machO.readSymbolicMangledName(at: layout.param.resolveDirectFileOffset(from: offset(of: \.param)))
    }
}

//public enum GenericRequirementKindWrapper {
//    
//    case type(RelativeIndirectablePointer<ProtocolConformanceDescriptor>)
//    case `protocol`(Relative)
//}
