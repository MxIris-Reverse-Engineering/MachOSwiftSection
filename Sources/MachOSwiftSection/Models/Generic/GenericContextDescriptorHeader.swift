//
//  GenericContextDescriptorHeader.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/2.
//


public struct GenericContextDescriptorHeader: LocatableLayoutWrapper {
    public struct Layout {
        public let numParams: UInt16
        public let numRequirements: UInt16
        public let numKeyArguments: UInt16
        public let flags: GenericContextDescriptorFlags
    }
    
    public let offset: Int
    public var layout: Layout
    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}
