//
//  RelativeIndirectablePointerProtocol.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/7.
//

import MachOKit

public protocol RelativeIndirectablePointerProtocol: RelativeDirectPointerProtocol, RelativeIndirectPointerProtocol {
    var isIndirect: Bool { get }
    func resolveIndirectableFileOffset(from fileOffset: Int, in machO: MachOFile) throws -> Int
}

extension RelativeIndirectablePointerProtocol {
    public func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Pointee {
        return try resolveIndirectable(from: fileOffset, in: machO)
    }

    public func resolve<T>(from fileOffset: Int, in machO: MachOFile) throws -> T {
        return try resolveIndirectableAny(from: fileOffset, in: machO)
    }

    func resolveIndirectable(from fileOffset: Int, in machO: MachOFile) throws -> Pointee {
        if isIndirect {
            return try resolveIndirect(from: fileOffset, in: machO)
        } else {
            return try resolveDirect(from: fileOffset, in: machO)
        }
    }

    func resolveIndirectableType(from fileOffset: Int, in machO: MachOFile) throws -> IndirectType? {
        guard isIndirect else { return nil }
        return try resolveIndirectableType(from: fileOffset, in: machO)
    }

    func resolveIndirectableAny<T>(from fileOffset: Int, in machO: MachOFile) throws -> T {
        if isIndirect {
            return try resolveIndirect(from: fileOffset, in: machO)
        } else {
            return try resolveDirect(from: fileOffset, in: machO)
        }
    }

    public func resolveIndirectableFileOffset(from fileOffset: Int, in machO: MachOFile) throws -> Int {
        guard let indirectType = try resolveIndirectableType(from: fileOffset, in: machO) else { return resolveDirectFileOffset(from: fileOffset) }
        return indirectType.resolveOffset(in: machO)
    }
}

extension RelativeIndirectablePointerProtocol where Pointee: RelativePointerOptional {
    public func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Pointee {
        guard isValid else { return nil }
        let result: Pointee.Wrapped = try resolve(from: fileOffset, in: machO)
        return .makeOptional(from: result)
    }
}


