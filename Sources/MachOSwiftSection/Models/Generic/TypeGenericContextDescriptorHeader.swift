//
//  TypeGenericContextDescriptorHeader.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/2.
//


public struct TypeGenericContextDescriptorHeader: LocatableLayoutWrapper {
    public struct Layout {
        public let instantiationCache: RelativeOffset
        public let defaultInstantiationPattern: RelativeOffset
        public let base: GenericContextDescriptorHeader
    }

    public let offset: Int
    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
    
}
