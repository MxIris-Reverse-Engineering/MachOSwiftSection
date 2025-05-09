//
//  ContextDescriptorProtocol.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/5.
//

import MachOKit

public protocol ContextDescriptorProtocol: LocatableLayoutWrapper where Layout: ContextDescriptorLayout {}

extension ContextDescriptorProtocol {
    public func parent(in machO: MachOFile) throws -> ContextDescriptorWrapper? {
        try layout.parent.resolve(from: offset + 4, in: machO)
    }

    public func genericContext(in machO: MachOFile) throws -> GenericContext? {
        return try .init(contextDescriptor: self, in: machO)
    }
}
