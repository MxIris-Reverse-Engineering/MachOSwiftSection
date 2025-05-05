//
//  NamedContextDescriptorProtocol.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/5.
//

import MachOKit

public protocol NamedContextDescriptorProtocol: ContextDescriptorProtocol where Layout: NamedContextDescriptorLayout {}

extension NamedContextDescriptorProtocol {
    public func name(in machO: MachOFile) throws -> String {
        try layout.name.resolve(from: 8 + offset, in: machO)
    }
}
