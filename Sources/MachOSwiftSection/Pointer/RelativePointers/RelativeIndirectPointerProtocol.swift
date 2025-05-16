//
//  RelativeIndirectPointerProtocol.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/7.
//

import MachOKit

public protocol RelativeIndirectPointerProtocol: RelativePointer {
    associatedtype IndirectType: RelativeIndirectType where IndirectType.Pointee == Pointee
    func resolveIndirectFileOffset(from fileOffset: Int, in machOFile: MachOFile) throws -> Int
}

extension RelativeIndirectPointerProtocol {
    public func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Pointee {
        return try resolveIndirect(from: fileOffset, in: machOFile)
    }

    func resolveIndirect(from fileOffset: Int, in machOFile: MachOFile) throws -> Pointee {
        return try resolveIndirectType(from: fileOffset, in: machOFile).resolve(in: machOFile)
    }

    public func resolveAny<T>(from fileOffset: Int, in machOFile: MachOFile) throws -> T {
        return try resolveIndirect(from: fileOffset, in: machOFile)
    }

    func resolveIndirect<T>(from fileOffset: Int, in machOFile: MachOFile) throws -> T {
        return try resolveIndirectType(from: fileOffset, in: machOFile).resolveAny(in: machOFile)
    }

    func resolveIndirectType(from fileOffset: Int, in machOFile: MachOFile) throws -> IndirectType {
        return try machOFile.readElement(offset: resolveDirectFileOffset(from: fileOffset))
    }

    public func resolveIndirectFileOffset(from fileOffset: Int, in machOFile: MachOFile) throws -> Int {
        return try resolveIndirectType(from: fileOffset, in: machOFile).resolveOffset(in: machOFile)
    }
}

extension RelativeIndirectPointerProtocol where Pointee: RelativePointerOptional {
    func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(from: fileOffset, in: machOFile)
    }
}
