import Foundation
@_spi(Support) import MachOKit

extension MachOFile {
    func makeSymbolicMangledNameStringRef(_ address: UInt64) -> String? {
        enum Element {
            struct Lookup {
                let kind: UInt8
                let address: UInt64
            }

            case string(String)
            case lookup(Lookup)
        }
        var elements: [Element] = []
        var currentOffset = address
        var currentString = ""
        while true {
            let value: UInt8 = fileHandle.read(offset: currentOffset + headerStartOffset.cast())
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

                let reference: Int32 = fileHandle.read(offset: currentOffset + 1 + headerStartOffset.cast())

                elements.append(.lookup(.init(kind: value, address: numericCast(Int(address + (currentOffset - address)) + Int(1 + reference)))))
                currentOffset += MemoryLayout<Int32>.size.cast()
            } else if value >= 0x18, value <= 0x1F {
                if currentString.count > 0 {
                    elements.append(.string(currentString))
                    currentString = ""
                }

                let reference: UInt64 = fileHandle.read(offset: currentOffset + 1 + headerStartOffset.cast())

                elements.append(.lookup(.init(kind: value, address: reference)))
                currentOffset += MemoryLayout<UInt64>.size.cast()
            } else {
                currentString.append(String(format: "%c", value))
            }
            currentOffset += MemoryLayout<UInt8>.size.cast()
        }

        var results: [String] = []
        var isBoundGeneric = false
        for (index, element) in elements.enumerated() {
            switch element {
            case var .string(string):
    //            results.append(makeDemangledTypeName(string, header: results.joined(separator: "")))
                results.append(string)
    //            if elements.count > 1 {
    //                if string.hasSuffix("y") {
    //                    isBoundGeneric = true
    //                    string = String(string.dropLast())
    //                } else if string == "G", index == elements.count - 1 {
    //                    continue
    //                } else if string.hasPrefix("y"), string.hasSuffix("G") {
    //                    string = String(string.dropFirst().dropLast())
    //                } else if index == elements.count - 1 {
    //                    string = string.hasSuffix("G") ? String(string.dropLast()) : string
    //                    if string == "G" {
    //                        continue
    //                    }
    //                    string = string.hasPrefix("_p") ? String(string.dropFirst(2)) : string
    //                    if string == "Qz" || string == "Qy_" || string == "Qy0_", results.count == 2 {
    //                        let tmp = results[0]
    //                        results[0] = results[1] + "." + tmp
    //                        results.removeSubrange(1 ..< results.count)
    //                    }
    //                }
    //            }
    //            if string.isEmpty {
    //                continue
    //            }
    //
    //
    ////            if regex1.matches(in: string, range: NSRange(location: 0, length: string.count)).count > 0 {
    ////                if string.contains("OS_dispatch_queue") {
    ////                    results.append("DispatchQueue")
    ////                } else {
    ////                    results.append("_$s" + string)
    ////                }
    ////            } else if regex2.matches(in: string, range: NSRange(location: 0, length: string.count)).count > 0 {
    ////                // remove leading numbers
    ////                var index = string.startIndex
    ////                while index < string.endIndex && string[index].isNumber {
    ////                    index = string.index(after: index)
    ////                }
    ////                if index < string.endIndex {
    ////                    results.append(String(string[index...]))
    ////                }
    ////            } else if string.hasPrefix("$s") {
    ////                results.append("_" + string)
    ////            } else {
    ////                if let demangled = MangledType[string] {
    ////                    results.append(demangled)
    ////                } else if string.hasPrefix("s") {
    ////                    if let demangled = MangledKnownTypeKind[String(string.dropFirst())] {
    ////                        results.append(demangled)
    ////                    }
    ////                } else {
    ////                    if isBoundGeneric {
    //                        results.append(string)
    ////                        results.append("->")
    ////                        isBoundGeneric = false
    ////                    } else {
    ////                        results.append("_$s" + string)
    ////                    }
    ////                }
    ////            }
            case let .lookup(lookup):
                if let (kind, directness) = SymbolicReference.symbolicReference(for: lookup.kind) {
                    switch kind {
                    case .context:
                        switch directness {
                        case .direct:
                            if let context = swift._readTypeContextDescriptor(from: lookup.address, in: self), var name = context.fieldDescriptor(in: self).mangledTypeName(in: self) {
    //                            var parent = context
    //                            if let currnetParent = parent.parent(in: machOFile), let parentName = currnetParent.name(in: machOFile) {
    //                                name = parentName + "." + name
    //                                parent = currnetParent
    //                            }
                                results.append(name)
                            }
                        case .indirect:
                            if let bind = resolveBind(at: fileOffset(of: lookup.address)), let symbolName = dyldChainedFixups?.symbolName(for: bind.0.info.nameOffset) {
                                results.append(symbolName)
                            } else if let rebase = resolveRebase(at: lookup.address), let context = swift._readTypeContextDescriptor(from: rebase, in: self), var name = context.fieldDescriptor(in: self).mangledTypeName(in: self) {
    //                            var parent = context
    //                            if let currnetParent = parent.parent(in: machOFile), let parentName = currnetParent.name(in: machOFile) {
    //                                name = parentName + "." + name
    //                                parent = currnetParent
    //                            }
                                results.append(name)
                            }
                        }
                    case .accessorFunctionReference:
                        fallthrough
                    case .uniqueExtendedExistentialTypeShape:
                        fallthrough
                    case .nonUniqueExtendedExistentialTypeShape:
                        fallthrough
                    case .objectiveCProtocol:
                        return nil
                    }
                }
            }
        }
        return results.joined(separator: "")

    }
}


//func makeSymbolicMangledNameStringRef(_ address: UInt64, in machOFile: MachOFile) -> String? {
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
//}
