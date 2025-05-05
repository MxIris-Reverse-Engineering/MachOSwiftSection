//
//  GenericRequirementDescriptor.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/2.
//


public struct GenericRequirementDescriptor: LayoutWrapperWithOffset {
    public struct Layout {
        public let flags: GenericRequirementFlags
        public let param: RelativeDirectPointer<String>
        public let typeOrProtocolOrConformanceOrLayoutOffset: RelativeOffset
    }

    public let offset: Int
    public var layout: Layout
    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}
