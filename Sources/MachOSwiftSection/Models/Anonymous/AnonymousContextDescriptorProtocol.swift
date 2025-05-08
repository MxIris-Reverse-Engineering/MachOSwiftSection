//
//  AnonymousContextDescriptorProtocol.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/5.
//

import MachOKit

public protocol AnonymousContextDescriptorProtocol: ContextDescriptorProtocol where Layout: AnonymousContextDescriptorLayout {}

extension AnonymousContextDescriptorProtocol {
    
    public func mangledName(in machO: MachOFile) throws -> MangledName? {
        guard let kindSpecificFlags = layout.flags.kindSpecificFlags, case let .anonymous(anonymousContextDescriptorFlags) = kindSpecificFlags, anonymousContextDescriptorFlags.hasMangledName else {
            return nil
        }
        var currentOffset = offset + layoutSize
        if let genericContext = try genericContext(in: machO) {
            currentOffset += genericContext.size
        }
        let mangledNamePointer: RelativeDirectPointer<MangledName> = try machO.readElement(offset: currentOffset)
        return try mangledNamePointer.resolve(from: currentOffset, in: machO)
    }
}
