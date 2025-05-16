//
//  RelativeDirectPointerProtocol.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/7.
//

import MachOKit

public protocol RelativeDirectPointerProtocol<Pointee>: RelativePointer {}

extension RelativeDirectPointerProtocol {
    public func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Pointee {
        return try resolveDirect(from: fileOffset, in: machOFile)
    }

    func resolveDirect(from fileOffset: Int, in machOFile: MachOFile) throws -> Pointee {
        return try Pointee.resolve(from: resolveDirectFileOffset(from: fileOffset), in: machOFile)
    }

    public func resolveAny<T>(from fileOffset: Int, in machOFile: MachOFile) throws -> T {
        return try resolveDirect(from: fileOffset, in: machOFile)
    }

    func resolveDirect<T>(from fileOffset: Int, in machOFile: MachOFile) throws -> T {
        return try machOFile.readElement(offset: resolveDirectFileOffset(from: fileOffset))
    }
}

extension RelativeDirectPointerProtocol where Pointee: RelativePointerOptional {
    func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(from: fileOffset, in: machOFile)
    }
}
