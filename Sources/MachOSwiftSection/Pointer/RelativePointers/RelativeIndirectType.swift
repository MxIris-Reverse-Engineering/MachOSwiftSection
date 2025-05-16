//
//  RelativeIndirectType.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/7.
//

import MachOKit

public protocol RelativeIndirectType {
    associatedtype Pointee: ResolvableElement
    func resolve(in machOFile: MachOFile) throws -> Pointee
    func resolveAny<T>(in machOFile: MachOFile) throws -> T
    func resolveOffset(in machOFile: MachOFile) -> Int
}

extension RelativeIndirectType {
    public func resolveAny<T>(in machOFile: MachOFile) throws -> T {
        return try machOFile.readElement(offset: resolveOffset(in: machOFile))
    }

    public func resolve(in machOFile: MachOFile) throws -> Pointee {
        return try Pointee.resolve(from: resolveOffset(in: machOFile), in: machOFile)
    }
}
