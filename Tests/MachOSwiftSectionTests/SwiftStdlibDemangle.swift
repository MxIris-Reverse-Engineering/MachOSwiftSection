import Foundation

@_silgen_name("swift_demangle")
internal func _stdlib_demangleImpl(
    mangledName: UnsafePointer<CChar>?,
    mangledNameLength: UInt,
    outputBuffer: UnsafeMutablePointer<CChar>?,
    outputBufferSize: UnsafeMutablePointer<UInt>?,
    flags: UInt32
) -> UnsafeMutablePointer<CChar>?

internal func stdlib_demangleName(
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

internal func stdlib_demangleName(
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
