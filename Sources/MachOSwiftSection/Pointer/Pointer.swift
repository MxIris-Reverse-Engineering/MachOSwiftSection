//
//  Pointer.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/7.
//

import MachOKit

public struct Pointer<Pointee: ResolvableElement>: RelativeIndirectType {
    public let address: UInt64

    public func resolveOffset(in machOFile: MachOFile) -> Int {
        if let cache = machOFile.cache, cache.cpu.type == .arm64 {
            numericCast(address & 0x7FFFFFFF)
        } else {
            numericCast(machOFile.fileOffset(of: address))
        }
    }
}

extension Pointer: ResolvableElement where Pointee: ResolvableElement {}

public typealias RawPointer = Pointer<AnyResolvableElement>


