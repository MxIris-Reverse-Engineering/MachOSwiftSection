//
//  RelativeDirectPointerProtocol.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/7.
//

import MachOKit

public protocol RelativeDirectPointerProtocol<Pointee>: RelativePointer {}

extension RelativeDirectPointerProtocol {
    public func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Pointee {
        return try resolveDirect(from: fileOffset, in: machO)
    }

    func resolveDirect(from fileOffset: Int, in machO: MachOFile) throws -> Pointee {
        return try Pointee.resolve(from: resolveDirectFileOffset(from: fileOffset), in: machO)
    }

    public func resolve<T>(from fileOffset: Int, in machO: MachOFile) throws -> T {
        return try resolveDirect(from: fileOffset, in: machO)
    }

    func resolveDirect<T>(from fileOffset: Int, in machO: MachOFile) throws -> T {
        return try machO.readElement(offset: resolveDirectFileOffset(from: fileOffset))
    }
}

extension RelativeDirectPointerProtocol where Pointee: RelativePointerOptional {
    func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Pointee {
        guard isValid else { return nil }
        return try resolve(from: fileOffset, in: machO)
    }
}
