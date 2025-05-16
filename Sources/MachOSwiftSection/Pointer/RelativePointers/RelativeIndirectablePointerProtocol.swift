//
//  RelativeIndirectablePointerProtocol.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/7.
//

import MachOKit

public protocol RelativeIndirectablePointerProtocol: RelativeDirectPointerProtocol, RelativeIndirectPointerProtocol {
    var isIndirect: Bool { get }
    func resolveIndirectableFileOffset(from fileOffset: Int, in machOFile: MachOFile) throws -> Int
}

extension RelativeIndirectablePointerProtocol {
    public func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Pointee {
        return try resolveIndirectable(from: fileOffset, in: machOFile)
    }

    public func resolveAny<T>(from fileOffset: Int, in machOFile: MachOFile) throws -> T {
        return try resolveIndirectableAny(from: fileOffset, in: machOFile)
    }

    func resolveIndirectable(from fileOffset: Int, in machOFile: MachOFile) throws -> Pointee {
        if isIndirect {
            return try resolveIndirect(from: fileOffset, in: machOFile)
        } else {
            return try resolveDirect(from: fileOffset, in: machOFile)
        }
    }

    func resolveIndirectableType(from fileOffset: Int, in machOFile: MachOFile) throws -> IndirectType? {
        guard isIndirect else { return nil }
        return try resolveIndirectableType(from: fileOffset, in: machOFile)
    }

    func resolveIndirectableAny<T>(from fileOffset: Int, in machOFile: MachOFile) throws -> T {
        if isIndirect {
            return try resolveIndirect(from: fileOffset, in: machOFile)
        } else {
            return try resolveDirect(from: fileOffset, in: machOFile)
        }
    }

    public func resolveIndirectableFileOffset(from fileOffset: Int, in machOFile: MachOFile) throws -> Int {
        guard let indirectType = try resolveIndirectableType(from: fileOffset, in: machOFile) else { return resolveDirectFileOffset(from: fileOffset) }
        return indirectType.resolveOffset(in: machOFile)
    }
}

extension RelativeIndirectablePointerProtocol where Pointee: RelativePointerOptional {
    func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(from: fileOffset, in: machOFile)
    }
}


