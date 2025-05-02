//
//  GenericRequirementDescriptor.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/2.
//


public struct GenericRequirementDescriptor: LayoutWrapperWithOffset {
    public struct Layout {
        public let flags: GenericRequirementFlags
        public let paramOffset: RelativeDirectPointer
        public let typeOrProtocolOrConformanceOrLayoutOffset: RelativeDirectPointer
    }

    public let offset: Int
    public var layout: Layout
    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }
}