//
//  GenericPackShapeHeader.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/2.
//


public struct GenericPackShapeHeader: LayoutWrapperWithOffset {
    public struct Layout {
        public let numPacks: UInt16
        public let numShapeClasses: UInt16
    }

    public let offset: Int
    public var layout: Layout
    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }
}