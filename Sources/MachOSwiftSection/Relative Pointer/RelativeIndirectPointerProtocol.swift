//
//  RelativeIndirectPointerProtocol.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/7.
//

import MachOKit

public protocol RelativeIndirectPointerProtocol: RelativePointer {
    associatedtype IndirectType: RelativeIndirectType where IndirectType.Pointee == Pointee
    func resolveIndirectFileOffset(from fileOffset: Int, in machO: MachOFile) throws -> Int
}

extension RelativeIndirectPointerProtocol {
    public func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Pointee {
        return try resolveIndirect(from: fileOffset, in: machO)
    }

    func resolveIndirect(from fileOffset: Int, in machO: MachOFile) throws -> Pointee {
        return try resolveIndirectType(from: fileOffset, in: machO).resolve(in: machO)
    }

    public func resolve<T>(from fileOffset: Int, in machO: MachOFile) throws -> T {
        return try resolveIndirect(from: fileOffset, in: machO)
    }

    func resolveIndirect<T>(from fileOffset: Int, in machO: MachOFile) throws -> T {
        return try resolveIndirectType(from: fileOffset, in: machO).resolveAny(in: machO)
    }

    func resolveIndirectType(from fileOffset: Int, in machO: MachOFile) throws -> IndirectType {
        return try read(offset: resolveDirectFileOffset(from: fileOffset), in: machO)
    }

    public func resolveIndirectFileOffset(from fileOffset: Int, in machO: MachOFile) throws -> Int {
        return try resolveIndirectType(from: fileOffset, in: machO).resolveOffset(in: machO)
    }
}

extension RelativeIndirectPointerProtocol where Pointee: RelativePointerOptional {
    func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(from: fileOffset, in: machO)
    }
}
