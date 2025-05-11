//
//  Pointer.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/7.
//

import MachOKit

public struct Pointer<Pointee: ResolvableElement>: RelativeIndirectType {
    public let address: UInt64

    public func resolveOffset(in machO: MachOFile) -> Int {
//        if machO.cache != nil, let offset = machO.cacheAndFileOffset(for: address) {
//            numericCast(offset.1)
//        } else {
            numericCast(machO.fileOffset(of: address))
//        }
    }
}

public struct SignedPointer<Pointee: ResolvableElement>: RelativeIndirectType {
    public let address: UInt64

    public func resolveOffset(in machO: MachOFile) -> Int {
//        if machO.cache != nil, let offset = machO.cacheAndFileOffset(for: address) {
//            numericCast(offset.1)
//        } else {
            numericCast(machO.fileOffset(of: address))
//        }
    }
}

public typealias SignedContextPointer<Context: ContextDescriptorProtocol> = SignedPointer<Context>

extension Pointer: ResolvableElement where Pointee: ResolvableElement {}
