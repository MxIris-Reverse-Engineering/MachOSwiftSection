import Foundation
import Darwin
@_spi(Support) import MachOKit

@_silgen_name("swift_demangle")
public func _stdlib_demangleImpl(
    mangledName: UnsafePointer<CChar>?,
    mangledNameLength: UInt,
    outputBuffer: UnsafeMutablePointer<CChar>?,
    outputBufferSize: UnsafeMutablePointer<UInt>?,
    flags: UInt32
) -> UnsafeMutablePointer<CChar>?

func _stdlib_demangleName(_ mangledName: String) -> String {
    return mangledName.utf8CString.withUnsafeBufferPointer {
        mangledNameUTF8CStr in

        let demangledNamePtr = _stdlib_demangleImpl(
            mangledName: mangledNameUTF8CStr.baseAddress,
            mangledNameLength: UInt(mangledNameUTF8CStr.count - 1),
            outputBuffer: nil,
            outputBufferSize: nil,
            flags: 0
        )

        if let demangledNamePtr = demangledNamePtr {
            let demangledName = String(cString: demangledNamePtr)
            free(demangledNamePtr)
            return demangledName
        }
        return mangledName
    }
}

func swift_demangle(_ mangled: String) -> String? {
    let result = _stdlib_demangleName(mangled).replacingOccurrences(of: "$s", with: "").replacingOccurrences(of: "__C.", with: "")
    if result.contains("for "), let s = result.components(separatedBy: "for ").last {
        return s
    }
    return fixOptionalTypeName(result)
}

@_silgen_name("swift_getTypeByMangledNameInContext")
public func _getTypeByMangledNameInContext(
    _ name: UnsafePointer<UInt8>,
    _ nameLength: Int,
    genericContext: UnsafeRawPointer?,
    genericArguments: UnsafeRawPointer?
) -> Any.Type?

func canDemangleFromRuntime(_ instr: String) -> Bool {
    return instr.hasPrefix("So") || instr.hasPrefix("$So") || instr.hasPrefix("_$So") || instr.hasPrefix("_T")
}

func runtimeGetDemangledName(_ instr: String) -> String {
    var str: String = instr
    if instr.hasPrefix("$s") {
        str = instr
    } else if instr.hasPrefix("So") {
        str = "$s" + instr
    } else if instr.hasPrefix("_T") {
        //
    } else {
        return instr
    }

    if let s = swift_demangle(str) {
        return s
    }
    return instr
}

func getTypeFromMangledName(_ str: String) -> String {
    if str.hasSuffix("0x") {
        return str
    }
    if canDemangleFromRuntime(str) {
        return runtimeGetDemangledName(str)
    }
    // check is ascii string
    if !str.isAsciiString() {
        return str
    }

    guard let ptr = str.toPointer() else {
        return str
    }

    var useCnt: Int = str.count
    if str.contains("_pG") {
        useCnt = useCnt - str.components(separatedBy: "_pG").first!.count
    }

    guard let typeRet: Any.Type = _getTypeByMangledNameInContext(ptr, useCnt, genericContext: nil, genericArguments: nil) else {
        return str
    }

    return fixOptionalTypeName(String(describing: typeRet))
}

func fixOptionalTypeName(_ typeName: String) -> String {
    if typeName.contains("Optional") {
        var result = typeName.replacingOccurrences(of: "Swift.Optional", with: "").replacingOccurrences(of: "Optional", with: "")
        if let s = result.firstIndex(of: "<") {
            result.remove(at: s)
            if let e = result.lastIndex(of: ">") {
                result.remove(at: e)
            }
        }
        return result + "?"
    }
    return typeName
}

func makeDemangledTypeName(_ type: String, header: String) -> String {
    if type.hasPrefix("_$") {
        return header + type.replacingOccurrences(of: "_$", with: "_")
    }
    let isArray: Bool = header.contains("Say") || header.contains("SDy")
    let suffix: String = isArray ? "G" : ""
    let fixName = "So\(type.count)\(type)C" + suffix
    return fixName
}

private let regex1 = try! NSRegularExpression(pattern: "So[0-9]+")

private let regex2 = try! NSRegularExpression(pattern: "^[0-9]+")



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
    "Bb":        "Builtin.BridgeObject",
    "BB":        "Builtin.UnsafeValueBuffer",
    "Bc":        "Builtin.RawUnsafeContinuation",
    "BD":        "Builtin.DefaultActorStorage",
    "Be":        "Builtin.Executor",
    "Bd":        "Builtin.NonDefaultDistributedActorStorage",
    "Bf":        "Builtin.Float<n>",
    "Bi":        "Builtin.Int<n>",
    "BI":        "Builtin.IntLiteral",
    "Bj":        "Builtin.Job",
    "BP":        "Builtin.PackIndex",
    "BO":        "Builtin.UnknownObject",
    "Bo":        "Builtin.NativeObject",
    "Bp":        "Builtin.RawPointer",
    "Bt":        "Builtin.SILToken",
    "Bv":        "Builtin.Vec<n>x<type>",
    "Bw":        "Builtin.Word",
    "c":         "function type (escaping)",
    "X":         "special function type",
    "Sg":        "?", // shortcut for: type 'ySqG'
    "ySqG":      "?", // optional type
    "GSg":       "?",
    "_pSg":      "?",
    "SgSg":      "??",
    "ypG":       "Any",
    "p":         "Any",
    "SSG":       "String",
    "SSGSg":     "String?",
    "SSSgG":     "String?",
    "SpySvSgGG": "UnsafeMutablePointer<UNumberFormat?>",
    "SiGSg":     "Int?",
    "Xo":        "@unowned type",
    "Xu":        "@unowned(unsafe) type",
    "Xw":        "@weak type",
    "XF":        "function implementation type (currently unused)",
    "Xb":        "SIL @box type (deprecated)",
    "Xx":        "SIL box type",
    "XD":        "dynamic self type",
    "m":         "metatype without representation",
    "XM":        "metatype with representation",
    "Xp":        "existential metatype without representation",
    "Xm":        "existential metatype with representation",
    "Xe":        "(error)",
    "x":         "A", // generic param, depth=0, idx=0
    "q_":        "B", // dependent generic parameter
    "yxq_G":     "<A, B>",
    "xq_":       "<A, B>",
    "Sb":        "Swift.Bool",
    "Qz":        "==",
    "Qy_":       "==",
    "Qy0_":      "==",
    "SgXw":      "?",
]
