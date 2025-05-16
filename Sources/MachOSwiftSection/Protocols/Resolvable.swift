//
//  ResolvableElement.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/7.
//

import MachOKit

public protocol Resolvable {
    static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self
    static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self?
}

extension Resolvable {
    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self {
        return try machOFile.readElement(offset: fileOffset)
    }

    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self? {
        let result: Self = try resolve(from: fileOffset, in: machOFile)
        return .some(result)
    }
}

extension Optional: Resolvable where Wrapped: Resolvable {
    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self {
        let result: Wrapped? = try Wrapped.resolve(from: fileOffset, in: machOFile)
        if let result {
            return .some(result)
        } else {
            return .none
        }
    }
}

extension String: Resolvable {
    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self {
        return try machOFile.readString(offset: fileOffset) ?? ""
    }
}

extension Resolvable where Self: LocatableLayoutWrapper {
    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self {
        let layout: Layout = try machOFile.readElement(offset: fileOffset)
        return .init(layout: layout, offset: fileOffset)
    }
}

extension ContextDescriptorWrapper: Resolvable {
    public static func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Self? {
        guard let contextDescriptor = try machO.swift._readContextDescriptor(from: fileOffset) else { return nil }
        return contextDescriptor
    }
}
