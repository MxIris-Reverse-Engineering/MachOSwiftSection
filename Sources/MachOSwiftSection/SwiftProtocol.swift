//
//  SwiftProtocol.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/4/23.
//

import Foundation
@_spi(Support) import MachOKit

public struct SwiftProtocol: LayoutWrapper, SwiftProtocolProtocol {
    public typealias LayoutField = SwiftProtocolLayoutField

    public struct Layout: _SwiftProtocolLayoutProtocol {
        public typealias Pointer = Int32

        public var flags: UInt32

        public var parent: Int32

        public var name: Int32

        public var numRequirementsInSignature: UInt32

        public var numRequirements: UInt32

        public var associatedTypes: Int32
    }

    public var layout: Layout
    public var offset: Int

    @_spi(Core)
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }

    public func layoutOffset(of field: LayoutField) -> Int {
        let keyPath: PartialKeyPath<Layout>

        switch field {
        case .flags:
            keyPath = \.flags
        case .parent:
            keyPath = \.parent
        case .name:
            keyPath = \.name
        case .numRequirementsInSignature:
            keyPath = \.numRequirementsInSignature
        case .numRequirements:
            keyPath = \.numRequirements
        case .associatedTypes:
            keyPath = \.associatedTypes
        }

        return layoutOffset(of: keyPath)
    }
}
