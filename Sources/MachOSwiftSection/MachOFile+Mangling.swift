import Foundation
import MachOKit

extension MachOFile {
    func makeSymbolicMangledNameStringRef(_ address: UInt64) throws -> String {
        enum Element {
            struct Lookup {
                enum Reference {
                    case relative(RelativeReference)
                    case absolute(AbsoluteReference)
                }

                struct RelativeReference {
                    let kind: SymbolicReference.Kind
                    let directness: SymbolicReference.Directness
                    let relativeOffset: RelativeOffset
                }

                struct AbsoluteReference {
                    let reference: UInt64
                }

                let offset: Int
                let reference: Reference
            }

            case string(String)
            case lookup(Lookup)
        }
        var elements: [Element] = []
        var currentOffset = address
        var currentString = ""
        while true {
            let value: UInt8 = try fileHandle.read(offset: currentOffset + headerStartOffset.cast())
            if value == 0xFF {}
            else if value == 0 {
                if currentString.count > 0 {
                    elements.append(.string(currentString))
                    currentString = ""
                }
                break
            } else if value >= 0x01, value <= 0x17 {
                if currentString.count > 0 {
                    elements.append(.string(currentString))
                    currentString = ""
                }
                if let (kind, directness) = SymbolicReference.symbolicReference(for: value) {
                    let reference: Int32 = try fileHandle.read(offset: currentOffset + 1 + headerStartOffset.cast())
                    let offset = Int(address + (currentOffset - address))
                    elements.append(.lookup(.init(offset: offset, reference: .relative(.init(kind: kind, directness: directness, relativeOffset: reference + 1)))))
                }
                currentOffset.offset(of: Int32.self)
            } else if value >= 0x18, value <= 0x1F {
                if currentString.count > 0 {
                    elements.append(.string(currentString))
                    currentString = ""
                }

                let reference: UInt64 = try fileHandle.read(offset: currentOffset + 1 + headerStartOffset.cast())
                let offset = Int(address + (currentOffset - address))
                elements.append(.lookup(.init(offset: offset, reference: .absolute(.init(reference: reference)))))
                currentOffset.offset(of: UInt64.self)
            } else {
                currentString.append(String(format: "%c", value))
            }
            currentOffset.offset(of: UInt8.self)
        }

        var results: [String] = []
        for (_, element) in elements.enumerated() {
            switch element {
            case let .string(string):
                results.append(string)
            case let .lookup(lookup):
                switch lookup.reference {
                case let .relative(relativeReference):
                    switch relativeReference.kind {
                    case .context:
                        switch relativeReference.directness {
                        case .direct:
                            if let context = try RelativeDirectPointer<ContextDescriptor>(relativeOffset: relativeReference.relativeOffset).resolveContextDescriptor(from: lookup.offset, in: self) {
                                let name: String? = switch context {
                                case let .type(typeContextDescriptor):
                                    if try typeContextDescriptor.fieldDescriptor(in: self).address(of: \.mangledTypeName) == address {
                                        try typeContextDescriptor.name(in: self)
                                    } else {
                                        try typeContextDescriptor.fieldDescriptor(in: self).mangledTypeName(in: self)
                                    }
                                case let .protocol(protocolDescriptor):
                                    try protocolDescriptor.name(in: self)
                                default:
                                    nil
                                }

                                //                            var parent = context
                                //                            if let currnetParent = parent.parent(in: machOFile), let parentName = currnetParent.name(in: machOFile) {
                                //                                name = parentName + "." + name
                                //                                parent = currnetParent
                                //                            }
                                if let name {
                                    results.append(name)
                                }
                            }
                        case .indirect:
                            let relativePointer = RelativeIndirectPointer<ContextDescriptor>(relativeOffset: relativeReference.relativeOffset)
                            if let bind = try resolveBind(at: lookup.offset, for: relativePointer), let symbolName = dyldChainedFixups?.symbolName(for: bind.0.info.nameOffset) {
                                results.append(symbolName)
                            } else if let context = try relativePointer.resolveContextDescriptor(from: lookup.offset, in: self) {
                                let name: String? = switch context {
                                case let .type(typeContextDescriptor):
                                    if try typeContextDescriptor.fieldDescriptor(in: self).address(of: \.mangledTypeName) == address {
                                        try typeContextDescriptor.name(in: self)
                                    } else {
                                        try typeContextDescriptor.fieldDescriptor(in: self).mangledTypeName(in: self)
                                    }
                                case let .protocol(protocolDescriptor):
                                    try protocolDescriptor.name(in: self)
                                default:
                                    nil
                                }
                                //                            var parent = context
                                //                            if let currnetParent = parent.parent(in: machOFile), let parentName = currnetParent.name(in: machOFile) {
                                //                                name = parentName + "." + name
                                //                                parent = currnetParent
                                //                            }
                                if let name {
                                    results.append(name)
                                }
                            }
                        }
                    case .accessorFunctionReference:
                        break
                    case .uniqueExtendedExistentialTypeShape:
                        break
                    case .nonUniqueExtendedExistentialTypeShape:
                        break
                    case .objectiveCProtocol:
                        let relativePointer = RelativeDirectPointer<ObjCProtocolDecl>(relativeOffset: relativeReference.relativeOffset)
                        let objcProtocol = try relativePointer.resolve(from: lookup.offset, in: self)
                        try results.append(objcProtocol.mangledName(in: self))
                    }
                case .absolute:
                    continue
                }
            }
        }
        return results.joined(separator: "")
    }
}

// func makeSymbolicMangledNameStringRef(_ address: UInt64, in machOFile: MachOFile) -> String? {
//    var mangledTypeName = ""
//    guard let mangledTypeNameOrStringRef = machOFile.fileHandle.readString(offset: address + numericCast(machOFile.headerStartOffset)) else { return nil }
//    if mangledTypeNameOrStringRef.starts(with: "0x") {
//        let hexName: String = mangledTypeNameOrStringRef.removingPrefix("0x")
//        var dataArray: [UInt8] = hexName.hexBytes
//        var i = 0
//        while i < dataArray.count {
//            let value = dataArray[i]
//            guard let (kind, directness) = SymbolicReference.symbolicReference(for: value) else {
//                mangledTypeName = mangledTypeName + String(format: "%c", value)
//                i = i + 1
//                continue
//            }
//            switch kind {
//            case .context:
//                switch directness {
//                case .direct:
//                    // find
//                    let fromIndex: Int = i + 1 // ignore 0x01
//                    let toIndex: Int = i + 5 // 4 bytes
//
//                    if toIndex > dataArray.count {
//                        dataArray.append(contentsOf: [UInt8](repeating: 0, count: toIndex - dataArray.count))
//                    }
//                    let offsetArray: [UInt8] = Array(dataArray[fromIndex ..< toIndex])
//
//                    let ptr = address + numericCast(fromIndex)
//
//                    let offset = offsetArray.withUnsafeBytes { rawBufferPointer in
//                        return rawBufferPointer.load(as: Int32.self)
//                    }
//
//                    let addrPtr: UInt64 = numericCast(Int(ptr) + Int(offset))
//
//                    if let name = machOFile.swift._readTypeContextDescriptor(from: addrPtr, in: machOFile)?.name(in: machOFile) {
//                        mangledTypeName += name
//                        if i == 0, toIndex >= dataArray.count {
//                            mangledTypeName = mangledTypeName + name
//                        } else {
//                            mangledTypeName = mangledTypeName + makeDemangledTypeName(name, header: mangledTypeName)
//                        }
//                    }
//                case .indirect:
//                    let fromIndex: Int = i + 1 // ignore 0x02
//                    let toIndex: Int = i + 5
//
//                    if toIndex > dataArray.count {
//                        dataArray.append(contentsOf: [UInt8](repeating: 0, count: toIndex - dataArray.count))
//                    }
//
//                    let offsetArray: [UInt8] = Array(dataArray[fromIndex ..< toIndex])
//
//                    let ptr = address + numericCast(fromIndex)
//
//                    let offset = offsetArray.withUnsafeBytes { rawBufferPointer in
//                        return rawBufferPointer.load(as: Int32.self)
//                    }
//                    let addrPtr: UInt64 = numericCast(Int(ptr) + Int(offset))
//
//                    if let bind = machOFile.resolveBind(at: machOFile.fileOffset(of: addrPtr)), let symbolName = machOFile.dyldChainedFixups?.symbolName(for: bind.0.info.nameOffset) {
//                        if i == 0, toIndex >= dataArray.count {
//                            mangledTypeName = mangledTypeName + symbolName
//                        } else {
//                            mangledTypeName = mangledTypeName + makeDemangledTypeName(symbolName, header: mangledTypeName)
//                        }
//                    } else if let rebase = machOFile.resolveRebase(at: addrPtr), let name = machOFile.swift._readTypeContextDescriptor(from: rebase, in: machOFile)?.name(in: machOFile) {
//                        if i == 0, toIndex >= dataArray.count {
//                            mangledTypeName = mangledTypeName + name
//                        } else {
//                            mangledTypeName = mangledTypeName + makeDemangledTypeName(name, header: mangledTypeName)
//                        }
//                    }
//
//                }
//            case .accessorFunctionReference:
//                break
//            case .uniqueExtendedExistentialTypeShape:
//                break
//            case .nonUniqueExtendedExistentialTypeShape:
//                break
//            case .objectiveCProtocol:
//                let fromIdx: Int = i + 1 // ignore 0x01
//                let toIdx: Int = i + 5 // 4 bytes
//                if toIdx > dataArray.count {
//                    dataArray.append(contentsOf: [UInt8](repeating: 0, count: toIdx - dataArray.count))
//                }
//                let offsetArray: [UInt8] = Array(dataArray[fromIdx ..< toIdx])
//
//                let ptr = address + numericCast(fromIdx)
//
//                let offset = offsetArray.withUnsafeBytes { rawBufferPointer in
//                    return rawBufferPointer.load(as: Int32.self)
//                }
//                let addrPtr: UInt64 = numericCast(Int(ptr) + Int(offset))
//                let offset2: Int32 = machOFile.fileHandle.read(offset: addrPtr + 4)
//                print(offset2, Int(addrPtr + 4) + Int(offset2), Int(ptr) + Int(offset2))
//                return nil
//            }
//
//            i = i + 5
//        }
//    } else {
//        return mangledTypeNameOrStringRef
//    }
//    return mangledTypeName
// }
