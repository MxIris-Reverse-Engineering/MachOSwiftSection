import Foundation
import MachOKit
import MachOObjCSection
import CrossReferenceCore

/// The instance variables an image's classes declare, by the unslid address
/// of each one's offset variable in `__objc_ivar` — what code loads to reach
/// an instance variable, `adrp` / `ldrsw` (or a 64-bit `ldr` from Swift).
///
/// Named by the image's `_OBJC_IVAR_$_<class>.<variable>` symbols first, then
/// by its classes' instance variable lists — each entry points at its offset
/// variable and at its name — which name the variables a stripped symbol
/// table leaves unnamed. Kept on the image's function table, read on the
/// first load from `__objc_ivar` a scan meets.
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

        // An entry is `{ offset variable, name, type, alignment, size }`;
        // where each list lies, MachOObjCSection reads per kind of reader.
        let records = if let image = table.image.reader.asMachOImage {
            Self.instanceVariableRecords(in: image)
        } else if let file = table.image.reader.asMachOFile {
            Self.instanceVariableRecords(in: file)
        } else {
            [(className: String, recordOffset: Int)]()
        }
        let memory = table.memory
        for (className, recordOffset) in records {
            guard let recordAddress = table.image.unslidAddress(ofReaderOffset: recordOffset) else { continue }
            let entry = table.runtimeAddress(ofUnslid: recordAddress)
            guard let slot = memory.pointer(at: entry), slot != 0,
                  let nameAddress = memory.pointer(at: entry &+ 8), nameAddress != 0,
                  let name = memory.typedPointer(to: CChar.self, at: nameAddress, length: 1)
            else { continue }
            record(className: className, name: String(cString: name), slot: table.unslidAddress(ofRuntime: slot))
        }
        self.instanceVariablesBySlot = variables
        self.approximateByteCount = stringByteCount + ApproximateSize.of(variables)
    }

    private static func instanceVariableRecords(in image: MachOImage) -> [(className: String, recordOffset: Int)] {
        var records: [(className: String, recordOffset: Int)] = []
        for classObject in image.objc.classes64 ?? [] {
            guard let readOnlyData = ObjectiveCClassIndex.readOnlyData(of: classObject, in: image),
                  let className = readOnlyData.name(in: image),
                  let list = readOnlyData.ivarList(in: image)
            else { continue }
            for variable in list.ivars(in: image) ?? [] { records.append((className, variable.offset)) }
        }
        return records
    }

    private static func instanceVariableRecords(in file: MachOFile) -> [(className: String, recordOffset: Int)] {
        var records: [(className: String, recordOffset: Int)] = []
        for classObject in file.objc.classes64 ?? [] {
            guard let readOnlyData = classObject.classROData(in: file),
                  let className = readOnlyData.name(in: file),
                  let list = readOnlyData.ivarList(in: file)
            else { continue }
            for variable in list.ivars(in: file) ?? [] { records.append((className, variable.offset)) }
        }
        return records
    }
}
