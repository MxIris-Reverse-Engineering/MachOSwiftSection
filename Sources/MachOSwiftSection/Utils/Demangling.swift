import Foundation
import Darwin
import MachOKit

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
