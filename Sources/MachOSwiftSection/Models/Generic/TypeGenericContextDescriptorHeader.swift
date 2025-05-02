//
//  TypeGenericContextDescriptorHeader.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/2.
//


public struct TypeGenericContextDescriptorHeader: LayoutWrapperWithOffset {
    public struct Layout {
        public let instantiationCache: RelativeDirectPointer
        public let defaultInstantiationPattern: RelativeDirectPointer
        public let base: GenericContextDescriptorHeader
    }

    public let offset: Int
    public var layout: Layout

    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }
    
}