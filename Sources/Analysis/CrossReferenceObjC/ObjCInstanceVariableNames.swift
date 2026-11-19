import Foundation
import MachOKit
@_spi(Internals) import MachOCodeReferences

/// The instance variables an image's classes declare, by the unslid address
/// of each one's offset variable in `__objc_ivar` — what code loads to reach
/// an instance variable, `adrp` / `ldrsw` (or a 64-bit `ldr` from Swift).
///
/// Named by the image's `_OBJC_IVAR_$_<class>.<variable>` symbols first, then
/// by its classes' instance variable lists — each entry points at its offset
/// variable and at its name — which name the variables a stripped symbol
/// table leaves unnamed. Kept on the image's function table, read on the
/// first load from `__objc_ivar` a scan meets.
///
/// The lists are read through the analyzer's memory, from `__objc_classlist`
/// on, not through MachOObjCSection: going through its classes looks up the
/// image's load commands again for every class, and reading every image's
/// lists that way made a scan of the whole cache 30% slower.
package final class ObjCInstanceVariableNames: ImageFunctionTableAttachment, @unchecked Sendable {
    package struct InstanceVariable: Hashable, Sendable {
        package let className: String
        package let name: String
    }

    package let instanceVariablesBySlot: [UInt64: InstanceVariable]
    package let approximateByteCount: Int

    package static func of(_ table: ImageFunctionTable) -> ObjCInstanceVariableNames {
        table.attachment(ObjCInstanceVariableNames.self) { ObjCInstanceVariableNames(table: table) }
    }

    private static let symbolPrefix = "_OBJC_IVAR_$_"

    private init(table: ImageFunctionTable) {
        var variables: [UInt64: InstanceVariable] = [:]
        var stringByteCount = 0
        func record(className: String, name: String, slot: UInt64) {
            guard variables[slot] == nil, !className.isEmpty, !name.isEmpty else { return }
            variables[slot] = InstanceVariable(className: className, name: name)
            stringByteCount += ApproximateSize.of(className) + ApproximateSize.of(name)
        }

        let linkEdit = ImageLinkEdit(image: table.image, memory: table.memory)
        Self.symbolPrefix.withCString { prefix in
            let prefixLength = strlen(prefix)
            for symbolIndex in linkEdit.symbols.indices {
                let entry = linkEdit.symbols[symbolIndex]
                guard ImageLinkEdit.isDefinedInSection(entry), let name = linkEdit.name(ofSymbolAt: symbolIndex), strncmp(name, prefix, prefixLength) == 0 else { continue }
                // `<class>.<variable>`: a variable's name holds no dot.
                let qualifiedName = String(cString: name + prefixLength)
                guard let dot = qualifiedName.lastIndex(of: ".") else { continue }
                record(className: String(qualifiedName[..<dot]), name: String(qualifiedName[qualifiedName.index(after: dot)...]), slot: entry.n_value)
            }
        }

        let memory = table.memory
        for section in table.sections where section.sectionName == "__objc_classlist" {
            let classes = memory.pointers(inSlotsAt: table.runtimeAddress(ofUnslid: UInt64(section.address)), count: section.size / 8)
            for classObject in classes where classObject != 0 {
                guard let readOnlyData = Self.readOnlyData(ofClassAt: classObject, in: memory),
                      let classNameAddress = memory.pointer(at: readOnlyData &+ Self.readOnlyNameOffset),
                      let className = Self.string(at: classNameAddress, in: memory),
                      let list = memory.pointer(at: readOnlyData &+ Self.readOnlyInstanceVariablesOffset), list != 0,
                      let header = memory.load(UInt64.self, at: list)
                else { continue }
                // `ivar_list_t`: `{ entsize, count }`, then the entries.
                let entrySize = UInt(header & 0xFFFF_FFFC)
                let count = Int(header >> 32)
                guard entrySize >= 16, count < 1 << 16 else { continue }
                for position in 0 ..< count {
                    // `ivar_t`: `{ offset, name, type, alignment, size }`.
                    let entry = list &+ 8 &+ UInt(position) &* entrySize
                    guard let slot = memory.pointer(at: entry), slot != 0,
                          let nameAddress = memory.pointer(at: entry &+ 8),
                          let name = Self.string(at: nameAddress, in: memory)
                    else { continue }
                    record(className: className, name: name, slot: table.unslidAddress(ofRuntime: slot))
                }
            }
        }
        self.instanceVariablesBySlot = variables
        self.approximateByteCount = stringByteCount + ApproximateSize.of(variables)
    }

    /// `class_ro_t.name` and `class_ro_t.ivars`, on 64-bit.
    private static let readOnlyNameOffset: UInt = 0x18
    private static let readOnlyInstanceVariablesOffset: UInt = 0x30

    /// The class's read-only data. Its data word, at +0x20, holds the data's
    /// address with flags in the low bits; once the runtime has realized the
    /// class — every class a process has used — it is a `class_rw_t`
    /// (`RW_REALIZED`, bit 31 of its flags, which a `class_ro_t` never sets)
    /// whose second word leads to the read-only data, directly or through a
    /// `class_rw_ext_t` when its low bit is set.
    private static func readOnlyData(ofClassAt classObject: UInt, in memory: any CrossReferenceMemory) -> UInt? {
        guard let dataWord = memory.pointer(at: classObject &+ 0x20) else { return nil }
        let data = dataWord & ~UInt(7)
        guard data != 0, let flags = memory.load(UInt32.self, at: data) else { return nil }
        guard flags & (1 << 31) != 0 else { return data }
        guard let readOnlyOrExtension = memory.load(UInt64.self, at: data &+ 8) else { return nil }
        let pointer = UInt(truncatingIfNeeded: readOnlyOrExtension) & memory.addressMask
        if pointer & 1 != 0 { return memory.pointer(at: pointer & ~UInt(1)) }
        return pointer
    }

    private static func string(at address: UInt, in memory: any CrossReferenceMemory) -> String? {
        guard address != 0, let characters = memory.typedPointer(to: CChar.self, at: address, length: 1) else { return nil }
        return String(cString: characters)
    }
}
