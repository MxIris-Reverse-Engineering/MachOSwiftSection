import Foundation
import MachOTestingSupportC

@_silgen_name("swift_demangle")
private func _stdlib_demangleImpl(
    mangledName: UnsafePointer<CChar>?,
    mangledNameLength: UInt,
    outputBuffer: UnsafeMutablePointer<CChar>?,
    outputBufferSize: UnsafeMutablePointer<UInt>?,
    flags: UInt32
) -> UnsafeMutablePointer<CChar>?

package func stdlib_demangleName(
    _ mangledName: String
) -> String {
    guard !mangledName.isEmpty else { return mangledName }
    return mangledName.utf8CString.withUnsafeBufferPointer { mangledNameUTF8 in
        let demangledNamePtr = _stdlib_demangleImpl(
            mangledName: mangledNameUTF8.baseAddress,
            mangledNameLength: numericCast(mangledNameUTF8.count - 1),
            outputBuffer: nil,
            outputBufferSize: nil,
            flags: 0
        )

        if let demangledNamePtr {
            return String(cString: demangledNamePtr)
        }
        return mangledName
    }
}

package func stdlib_demangleName(
    _ mangledName: UnsafePointer<CChar>
) -> UnsafePointer<CChar> {
    let demangledNamePtr = _stdlib_demangleImpl(
        mangledName: mangledName,
        mangledNameLength: numericCast(strlen(mangledName)),
        outputBuffer: nil,
        outputBufferSize: nil,
        flags: 0
    )
    if let demangledNamePtr {
        return .init(demangledNamePtr)
    }
    return mangledName
}

/// Returns the node tree string for a mangled Swift symbol name,
/// equivalent to `swift demangle --expand`.
package func stdlib_demangleNodeTree(_ mangledName: String) -> String? {
    guard let ptr = swift_demangle_getNodeTreeAsString(mangledName) else {
        return nil
    }
    let result = String(cString: ptr)
    free(ptr)
    return result
}
