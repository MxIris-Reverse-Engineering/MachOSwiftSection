import Foundation
import MachOKit

private let regex1 = try! NSRegularExpression(pattern: "So[0-9]+")

private let regex2 = try! NSRegularExpression(pattern: "^[0-9]+")

extension MachOFile {
    func readSymbolicMangledName(at fileOffset: Int) throws -> MangledName {
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
        var currentOffset = fileOffset
        var currentString = ""
        while true {
            let value: UInt8 = try fileHandle.read(offset: numericCast(currentOffset + headerStartOffset))
            if value == 0xFF {}
            else if value == 0 {
                if currentString.count > 0 {
                    elements.append(.string(currentString))
                    currentString = ""
                }
                currentOffset.offset(of: UInt8.self)
                break
            } else if value >= 0x01, value <= 0x17 {
                if currentString.count > 0 {
                    elements.append(.string(currentString))
                    currentString = ""
                }
                if let (kind, directness) = SymbolicReference.symbolicReference(for: value) {
                    let reference: Int32 = try fileHandle.read(offset: numericCast(currentOffset + 1 + headerStartOffset))
                    let offset = Int(fileOffset + (currentOffset - fileOffset))
                    elements.append(.lookup(.init(offset: offset, reference: .relative(.init(kind: kind, directness: directness, relativeOffset: reference + 1)))))
                }
                currentOffset.offset(of: Int32.self)
            } else if value >= 0x18, value <= 0x1F {
                if currentString.count > 0 {
                    elements.append(.string(currentString))
                    currentString = ""
                }

                let reference: UInt64 = try fileHandle.read(offset: numericCast(currentOffset + 1 + headerStartOffset))
                let offset = Int(fileOffset + (currentOffset - fileOffset))
                elements.append(.lookup(.init(offset: offset, reference: .absolute(.init(reference: reference)))))
                currentOffset.offset(of: UInt64.self)
            } else {
                currentString.append(String(format: "%c", value))
            }
            currentOffset.offset(of: UInt8.self)
        }

        var results: [String] = []
//        var isBoundGeneric = false

        for (index, element) in elements.enumerated() {
            func handleContextDescriptor(_ context: ContextDescriptorWrapper) throws {
                var name = ""
                switch context {
                case let .type(typeContextDescriptor):
                    name = try typeContextDescriptor.name(in: self).countedString
                case let .protocol(protocolDescriptor):
                    name = try protocolDescriptor.name(in: self).countedString
                default:
                    break
                }

                if let currnetParent = try context.contextDescriptor.parent(in: self), let parentName = try currnetParent.name(in: self) {
                    name = parentName.countedString + name
                }

                if index == 0 {
                    name = name.insertTypeManglePrefix
                }

                results.append(name + context.contextDescriptor.layout.flags.kind.mangledType)
            }
            switch element {
            case var .string(string):
                if index == 0 {
                    string = string.insertTypeManglePrefix
                }
                results.append(string)
//                if elements.count > 1 {
//                    if string.hasSuffix("y") {
//                        isBoundGeneric = true
            ////                        string = String(string.dropLast())
//                    } else if string == "G", index == elements.count - 1 {
//                        continue
//                    } else if string.hasPrefix("y"), string.hasSuffix("G") {
//                        string = String(string.dropFirst().dropLast())
//                    } else if index == elements.count - 1 {
//                        string = string.hasSuffix("G") ? String(string.dropLast()) : string
//                        if string == "G" {
//                            continue
//                        }
//                        string = string.hasPrefix("_p") ? String(string.dropFirst(2)) : string
//                        if string == "Qz" || string == "Qy_" || string == "Qy0_", results.count == 2 {
//                            let tmp = results[0]
//                            results[0] = results[1] + "." + tmp
//                            results.removeSubrange(1 ..< results.count)
//                        }
//                    }
//                }
//                if string.isEmpty {
//                    continue
//                }
//
//                if regex1.matches(in: string, range: NSRange(location: 0, length: string.count)).count > 0 {
//                    results.append("_$s" + string)
//                } else if regex2.matches(in: string, range: NSRange(location: 0, length: string.count)).count > 0 {
//                    // remove leading numbers
//                    var index = string.startIndex
//                    while index < string.endIndex && string[index].isNumber {
//                        index = string.index(after: index)
//                    }
//                    if index < string.endIndex {
//                        results.append(String(string[index...]))
//                    }
//                } else if string.hasPrefix("$s") {
//                    results.append("_" + string)
//                } else {
//                    if let demangled = MangledType[string] {
//                        results.append(demangled)
//                    } else if string.hasPrefix("s") {
//                        if let demangled = MangledKnownTypeKind[String(string.dropFirst())] {
//                            results.append(demangled)
//                        }
//                    } else {
//                        if isBoundGeneric {
//                            results.append(string)
//                            results.append("->")
//                            isBoundGeneric = false
//                        } else {
//                            results.append("_$s" + string)
//                        }
//                    }
//                }
            case let .lookup(lookup):
                switch lookup.reference {
                case let .relative(relativeReference):
                    switch relativeReference.kind {
                    case .context:
                        switch relativeReference.directness {
                        case .direct:
                            if let context = try RelativeDirectPointer<ContextDescriptorWrapper?>(relativeOffset: relativeReference.relativeOffset).resolve(from: lookup.offset, in: self) {
                                try handleContextDescriptor(context)
                            }
                        case .indirect:
                            let relativePointer = RelativeIndirectPointer<ContextDescriptorWrapper?, Pointer<ContextDescriptorWrapper?>>(relativeOffset: relativeReference.relativeOffset)
                            if let bind = try resolveBind(at: lookup.offset, for: relativePointer), var symbolName = dyldChainedFixups?.symbolName(for: bind.0.info.nameOffset) {
                                symbolName = symbolName.stripProtocolDescriptorMangle.stripNominalTypeDescriptorMangle.stripDuplicateProtocolMangleType
                                results.append(index != 0 ? symbolName.stripTypeManglePrefix : symbolName)
                            } else if let context = try relativePointer.resolve(from: lookup.offset, in: self) {
                                try handleContextDescriptor(context)
                            }
                        }
                    case .accessorFunctionReference:
                        break
                    case .uniqueExtendedExistentialTypeShape:
                        break
                    case .nonUniqueExtendedExistentialTypeShape:
                        break
                    case .objectiveCProtocol:
                        let relativePointer = RelativeDirectPointer<ObjCProtocolPrefix>(relativeOffset: relativeReference.relativeOffset)
                        let objcProtocol = try relativePointer.resolve(from: lookup.offset, in: self)
                        let name = try objcProtocol.mangledName(in: self).stringValue().stripProtocolDescriptorMangle.stripNominalTypeDescriptorMangle.stripDuplicateProtocolMangleType
                        results.append(index != 0 ? name.stripTypeManglePrefix : name)
                    }
                case .absolute:
                    continue
                }
            }
        }
        return .init(tokens: results, startOffset: fileOffset, endOffset: currentOffset)
    }
}

var MangledKnownTypeKind: [String: String] = [
    "A": "Swift.AutoreleasingUnsafeMutablePointer",
    "a": "Swift.Array",
    "B": "Swift.BinaryFloatingPoint",
    "b": "Swift.Bool",
    "c": "MangledKnownTypeKind2",
    "D": "Swift.Dictionary",
    "d": "Swift.Float64",
    "E": "Swift.Encodable",
    "e": "Swift.Decodable",
    "F": "Swift.FloatingPoint",
    "f": "Swift.Float32",
    "G": "Swift.RandomNumberGenerator",
    "H": "Swift.Hashable",
    "h": "Swift.Set",
    "I": "Swift.DefaultIndices",
    "i": "Swift.Int",
    "J": "Swift.Character",
    "j": "Swift.Numeric",
    "K": "Swift.BidirectionalCollection",
    "k": "Swift.RandomAccessCollection",
    "L": "Swift.Comparable",
    "l": "Swift.Collection",
    "M": "Swift.MutableCollection",
    "m": "Swift.RangeReplaceableCollection",
    "N": "Swift.ClosedRange",
    "n": "Swift.Range",
    "O": "Swift.ObjectIdentifier",
    "P": "Swift.UnsafePointer",
    "p": "Swift.UnsafeMutablePointer",
    "Q": "Swift.Equatable",
    "q": "Swift.Optional",
    "R": "Swift.UnsafeBufferPointer",
    "r": "Swift.UnsafeMutableBufferPointer",
    "S": "Swift.String",
    "s": "Swift.Substring",
    "T": "Swift.Sequence",
    "t": "Swift.IteratorProtocol",
    "U": "Swift.UnsignedInteger",
    "u": "Swift.UInt",
    "V": "Swift.UnsafeRawPointer",
    "v": "Swift.UnsafeMutableRawPointer",
    "W": "Swift.UnsafeRawBufferPointer",
    "w": "Swift.UnsafeMutableRawBufferPointer",
    "X": "Swift.RangeExpression",
    "x": "Swift.Strideable",
    "Y": "Swift.RawRepresentable",
    "y": "Swift.StringProtocol",
    "Z": "Swift.SignedInteger",
    "z": "Swift.BinaryInteger",
]

var MangledKnownTypeKind2: [String: String] = [
    "A": "Swift.Actor",
    "C": "Swift.CheckedContinuation",
    "c": "Swift.UnsafeContinuation",
    "E": "Swift.CancellationError",
    "e": "Swift.UnownedSerialExecutor",
    "F": "Swift.Executor",
    "f": "Swift.SerialExecutor",
    "G": "Swift.TaskGroup",
    "g": "Swift.ThrowingTaskGroup",
    "I": "Swift.AsyncIteratorProtocol",
    "i": "Swift.AsyncSequence",
    "J": "Swift.UnownedJob",
    "M": "Swift.MainActor",
    "P": "Swift.TaskPriority",
    "S": "Swift.AsyncStream",
    "s": "Swift.AsyncThrowingStream",
    "T": "Swift.Task",
    "t": "Swift.UnsafeCurrentTask",
]

// MangledType is a mangled type map
var MangledType: [String: String] = [
    "Bb": "Builtin.BridgeObject",
    "BB": "Builtin.UnsafeValueBuffer",
    "Bc": "Builtin.RawUnsafeContinuation",
    "BD": "Builtin.DefaultActorStorage",
    "Be": "Builtin.Executor",
    "Bd": "Builtin.NonDefaultDistributedActorStorage",
    "Bf": "Builtin.Float<n>",
    "Bi": "Builtin.Int<n>",
    "BI": "Builtin.IntLiteral",
    "Bj": "Builtin.Job",
    "BP": "Builtin.PackIndex",
    "BO": "Builtin.UnknownObject",
    "Bo": "Builtin.NativeObject",
    "Bp": "Builtin.RawPointer",
    "Bt": "Builtin.SILToken",
    "Bv": "Builtin.Vec<n>x<type>",
    "Bw": "Builtin.Word",
    "c": "function type (escaping)",
    "X": "special function type",
    "Sg": "?", // shortcut for: type 'ySqG'
    "ySqG": "?", // optional type
    "GSg": "?",
    "_pSg": "?",
    "SgSg": "??",
    "ypG": "Any",
    "p": "Any",
    "SSG": "String",
    "SSGSg": "String?",
    "SSSgG": "String?",
    "SpySvSgGG": "UnsafeMutablePointer<UNumberFormat?>",
    "SiGSg": "Int?",
    "Xo": "@unowned type",
    "Xu": "@unowned(unsafe) type",
    "Xw": "@weak type",
    "XF": "function implementation type (currently unused)",
    "Xb": "SIL @box type (deprecated)",
    "Xx": "SIL box type",
    "XD": "dynamic self type",
    "m": "metatype without representation",
    "XM": "metatype with representation",
    "Xp": "existential metatype without representation",
    "Xm": "existential metatype with representation",
    "Xe": "(error)",
    "x": "A", // generic param, depth=0, idx=0
    "q_": "B", // dependent generic parameter
    "yxq_G": "<A, B>",
    "xq_": "<A, B>",
    "Sb": "Swift.Bool",
    "Qz": "==",
    "Qy_": "==",
    "Qy0_": "==",
    "SgXw": "?",
]

extension String {
    var countedString: String {
        "\(count)\(self)"
    }

    var stripProtocolDescriptorMangle: String {
        replacingOccurrences(of: "Mp", with: "")
    }

    var stripNominalTypeDescriptorMangle: String {
        replacingOccurrences(of: "Mn", with: "")
    }

    var stripTypeManglePrefix: String {
        guard hasPrefix("_$s") else { return self }
        return replacingOccurrences(of: "_$s", with: "")
    }

    var insertTypeManglePrefix: String {
        "_$s" + self
    }

    var stripDuplicateProtocolMangleType: String {
        replacingOccurrences(of: "_p_p", with: "_p")
    }
}
