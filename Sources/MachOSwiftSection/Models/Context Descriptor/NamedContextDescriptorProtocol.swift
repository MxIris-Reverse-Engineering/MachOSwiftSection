//
//  NamedContextDescriptorProtocol.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/5.
//

import MachOKit

public protocol NamedContextDescriptorProtocol: ContextDescriptorProtocol where Layout: NamedContextDescriptorLayout {}

extension NamedContextDescriptorProtocol {
    public func name(in machOFile: MachOFile) throws -> String {
        try layout.name.resolve(from: 8 + offset, in: machOFile)
    }
    
    public func fullname(in machOFile: MachOFile) throws -> String {
        var name = try name(in: machOFile)
        var parent = try parent(in: machOFile)
        while let currnetParent = parent {
            if let parentName = try currnetParent.name(in: machOFile) {
                name = parentName + "." + name
            }
            parent = try currnetParent.contextDescriptor.parent(in: machOFile)
        }
        return name
    }
}
