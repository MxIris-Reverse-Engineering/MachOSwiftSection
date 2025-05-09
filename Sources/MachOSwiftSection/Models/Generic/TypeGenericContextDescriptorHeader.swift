//
//  TypeGenericContextDescriptorHeader.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/2.
//


public struct TypeGenericContextDescriptorHeader: GenericContextDescriptorHeaderProtocol {
    public struct Layout: GenericContextDescriptorHeaderLayout {
        public let instantiationCache: RelativeOffset
        public let defaultInstantiationPattern: RelativeOffset
        public let base: GenericContextDescriptorHeader
        
        public var numParams: UInt16 { base.numParams }
        public var numRequirements: UInt16 { base.numRequirements }
        public var numKeyArguments: UInt16 { base.numKeyArguments }
        public var flags: GenericContextDescriptorFlags { base.flags }
        
    }

    public let offset: Int
    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
    
}
