//
//  GenericPackShapeHeader.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/2.
//


public struct GenericPackShapeHeader: LocatableLayoutWrapper {
    public struct Layout {
        public let numPacks: UInt16
        public let numShapeClasses: UInt16
    }

    public let offset: Int
    public var layout: Layout
    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}
