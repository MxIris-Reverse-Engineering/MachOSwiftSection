import Foundation

/// The functions a scan marks as runtime helpers: memory management and
/// value operations, which outnumber everything else a function calls — in
/// a macOS 27.2 shared cache, 26.5% of all direct call targets.
enum RuntimeHelperNames {
    /// Symbol-name prefixes of helpers exported by libobjc and the Swift
    /// runtime, and of the helpers the Swift compiler emits into each image.
    private static let prefixes: [StaticString] = [
        "_objc_retain",
        "_objc_release",
        "_objc_autorelease",
        "_objc_storeStrong",
        "_objc_loadWeak",
        "_objc_storeWeak",
        "_objc_initWeak",
        "_objc_destroyWeak",
        "_objc_copyWeak",
        "_objc_moveWeak",
        "_objc_claimAutoreleasedReturnValue",
        "_objc_unsafeClaimAutoreleasedReturnValue",
        "_swift_retain",
        "_swift_release",
        "_swift_bridgeObjectRetain",
        "_swift_bridgeObjectRelease",
        "_swift_unknownObjectRetain",
        "_swift_unknownObjectRelease",
        "_swift_unknownObjectWeak",
        "_swift_unknownObjectUnowned",
        "_swift_unowned",
        "_swift_weak",
        "_swift_nonatomic_",
        "_swift_beginAccess",
        "_swift_endAccess",
        "___swift_destroy_boxed_opaque_existential",
        "___swift_allocate_boxed_opaque_existential",
        "___swift_project_boxed_opaque_existential",
        "___swift_memcpy",
        "___swift_noop",
    ]

    /// Whether the symbol named `name` is a runtime helper.
    static func isRuntimeHelper(_ name: UnsafePointer<CChar>) -> Bool {
        guard name[0] == 0x5F else { return false }
        if name[1] == 0x24 {
            return isOutlinedValueOperation(name)
        }
        guard name[1] == 0x6F || name[1] == 0x73 || name[1] == 0x5F else { return false }
        for prefix in prefixes {
            let matches = prefix.withUTF8Buffer { buffer in
                buffer.withMemoryRebound(to: CChar.self) { strncmp(name, $0.baseAddress!, buffer.count) == 0 }
            }
            if matches { return true }
        }
        return false
    }

    /// An outlined copy, destroy, retain or release: a mangled name ending in
    /// `WO` and a lowercase letter, perhaps merged (`Tm`).
    private static func isOutlinedValueOperation(_ name: UnsafePointer<CChar>) -> Bool {
        var length = strlen(name)
        if length > 2, name[length - 2] == 0x54, name[length - 1] == 0x6D { length -= 2 }
        guard length > 6 else { return false }
        let operation = name[length - 1]
        return name[length - 3] == 0x57 && name[length - 2] == 0x4F && operation >= 0x61 && operation <= 0x7A
    }
}
