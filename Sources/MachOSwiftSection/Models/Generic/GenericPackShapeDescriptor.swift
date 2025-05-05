//
//  GenericPackShapeDescriptor.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/2.
//


public struct GenericPackShapeDescriptor: LayoutWrapperWithOffset {
    public struct Layout {
        public let kind: GenericPackKind
        public let index: UInt16
        public let shapeClass: UInt16
        public let unused: UInt16
    }
    public let offset: Int
    public var layout: Layout
    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}
