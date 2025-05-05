//
//  ContextDescriptorProtocol.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/5.
//

import MachOKit

public protocol ContextDescriptorProtocol: LayoutWrapperWithOffset where Layout: ContextDescriptorLayout {}

extension ContextDescriptorProtocol {
    public func parent(in machO: MachOFile) throws -> ContextDescriptorWrapper? {
        try layout.parent.resolveContextDescriptor(from: offset + 4, in: machO)
    }
}
