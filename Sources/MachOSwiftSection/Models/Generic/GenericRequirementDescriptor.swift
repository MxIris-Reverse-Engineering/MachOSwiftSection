//
//  GenericRequirementDescriptor.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/2.
//

import Foundation
import MachOKit

public struct GenericRequirementDescriptor: LocatableLayoutWrapper {
    public struct Layout {
        public let flags: GenericRequirementFlags
        public let param: RelativeDirectPointer<MangledName>
        public let content: RelativeOffset
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension GenericRequirementDescriptor {
    func paramManagedName(in machOFile: MachOFile) throws -> MangledName {
        return try layout.param.resolve(from: fileOffset(of: \.param), in: machOFile)
    }

    func type(in machOFile: MachOFile) throws -> MangledName {
        return try RelativeDirectPointer<MangledName>(relativeOffset: layout.content).resolve(from: fileOffset(of: \.content), in: machOFile)
    }

    var content: GenericRequirementContent {
        switch layout.flags.kind {
        case .protocol:
            let ptr = RelativeIndirectableRawPointerIntPair<Bool>(relativeOffsetPlusIndirectAndInt: layout.content)
            if ptr.value {
                return .protocol(.objcPointer(.init(relativeOffsetPlusIndirectAndInt: layout.content)))
            } else {
                return .protocol(.swiftPointer(.init(relativeOffsetPlusIndirectAndInt: layout.content)))
            }
        case .sameType,
             .baseClass,
             .sameShape:
            return .type(.init(relativeOffset: layout.content))
        case .sameConformance:
            return .conformance(.init(relativeOffsetPlusIndirect: layout.content))
        case .invertedProtocols:
            var value = layout.content
            return .invertedProtocols(withUnsafeBytes(of: &value) {
                $0.baseAddress!.load(as: GenericRequirementContent.InvertedProtocols.self)
            })
        case .layout:
            return .layout(.init(rawValue: layout.content.cast())!)
        }
    }
    
    func resolvedContent(in machOFile: MachOFile) throws -> ResolvedGenericRequirementContent {
        let fileOffset = fileOffset(of: \.content)
        switch content {
        case .type(let relativeDirectPointer):
            return .type(try relativeDirectPointer.resolve(from: fileOffset, in: machOFile))
        case .protocol(let relativeProtocolDescriptorPointer):
            return .protocol(try relativeProtocolDescriptorPointer.resolve(from: fileOffset, in: machOFile))
        case .layout(let genericRequirementLayoutKind):
            return .layout(genericRequirementLayoutKind)
        case .conformance(let relativeIndirectablePointer):
            return .conformance(try relativeIndirectablePointer.resolve(from: fileOffset, in: machOFile))
        case .invertedProtocols(let invertedProtocols):
            return .invertedProtocols(invertedProtocols)
        }
    }
}


