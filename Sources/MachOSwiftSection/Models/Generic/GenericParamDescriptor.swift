//
//  GenericParamDescriptor.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/2.
//


public struct GenericParamDescriptor: LayoutWrapperWithOffset {
    public struct Layout {
        public let rawValue: UInt8
    }

    public let offset: Int
    public var layout: Layout

    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }

    public var hasKeyArgument: Bool {
        layout.rawValue & 0x80 != 0
    }

    public var kind: GenericParamKind {
        .init(rawValue: layout.rawValue & 0x3F)!
    }
}