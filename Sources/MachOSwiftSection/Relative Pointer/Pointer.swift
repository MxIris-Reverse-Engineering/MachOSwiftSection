//
//  Pointer.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/7.
//

import MachOKit

public struct Pointer<Pointee: ResolvableElement>: RelativeIndirectType {
    public typealias Element = Pointee
    public let address: UInt64

    public func resolveOffset(in machO: MachOFile) -> Int {
        numericCast(machO.fileOffset(of: address))
    }
}
