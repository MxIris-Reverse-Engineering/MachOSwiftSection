//
//  SignedPointer.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/15.
//

import MachOKit

public struct SignedPointer<Pointee: ResolvableElement>: RelativeIndirectType {
    public let address: UInt64

    public func resolveOffset(in machOFile: MachOFile) -> Int {
        if let cache = machOFile.cache, cache.cpu.type == .arm64 {
            numericCast(address & 0x7FFFFFFF)
        } else {
            numericCast(machOFile.fileOffset(of: address))
        }
    }
}


