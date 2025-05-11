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
    
    public func fullname(in machO: MachOFile) throws -> String {
        var name = try name(in: machO)
        var parent = try parent(in: machO)
        while let currnetParent = parent {
            if let parentName = try currnetParent.name(in: machO) {
                name = parentName + "." + name
            }
            parent = try currnetParent.contextDescriptor.parent(in: machO)
        }
        return name
    }
}
