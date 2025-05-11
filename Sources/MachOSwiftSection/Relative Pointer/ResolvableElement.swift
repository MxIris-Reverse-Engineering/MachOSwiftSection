//
//  ResolvableElement.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/7.
//

import MachOKit

public protocol ResolvableElement {
    static func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Self
    static func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Self?
}

extension ResolvableElement {
    public static func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Self {
        return try machO.readElement(offset: fileOffset)
    }

    public static func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Self? {
        let result: Self = try resolve(from: fileOffset, in: machO)
        return .some(result)
    }
}

extension Optional: ResolvableElement where Wrapped: ResolvableElement {
    public static func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Self {
        let result: Wrapped? = try Wrapped.resolve(from: fileOffset, in: machO)
        if let result {
            return .some(result)
        } else {
            return .none
        }
    }
}

extension String: ResolvableElement {
    public static func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Self {
        return try machO.readString(offset: fileOffset) ?? ""
    }
}

public struct AnyResolvableElement: ResolvableElement {
    public let wrappedValue: any ResolvableElement
}
