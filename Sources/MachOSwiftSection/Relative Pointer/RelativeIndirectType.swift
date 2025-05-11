//
//  RelativeIndirectType.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/7.
//

import MachOKit

public protocol RelativeIndirectType {
    associatedtype Pointee: ResolvableElement
    func resolve(in machO: MachOFile) throws -> Pointee
    func resolveAny<T>(in machO: MachOFile) throws -> T
    func resolveOffset(in machO: MachOFile) -> Int
}

extension RelativeIndirectType {
    public func resolveAny<T>(in machO: MachOFile) throws -> T {
        return try machO.readElement(offset: resolveOffset(in: machO))
    }

    public func resolve(in machO: MachOFile) throws -> Pointee {
        return try Pointee.resolve(from: resolveOffset(in: machO), in: machO)
    }
}
