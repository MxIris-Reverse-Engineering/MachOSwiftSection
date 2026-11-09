import Foundation
import MachOKit
import MachOSwiftSection
@_spi(Core) import MachOObjCSection

/// An Objective-C protocol record (`protocol_t`) as `__objc_protolist` lists
/// it, read in full. For an `@objc` protocol declared in Swift this is all the
/// binary keeps of its requirements: the compiler emits no Swift protocol
/// descriptor for it, and no Swift symbol for any requirement (evolution
/// proposal `swift-declared-objc-protocols`).
package struct ObjCProtocolRecord: Sendable, Hashable {
    package struct Method: Sendable, Hashable {
        package let selector: String
        /// The method list's type encoding (`@24@0:8@16`).
        package let typeEncoding: String
        /// The extended encoding, which names classes, protocols and block
        /// signatures (`@"NSString"24@0:8@"NSString"16`); `nil` when the
        /// record carries none.
        package let extendedTypeEncoding: String?
    }

    package struct Property: Sendable, Hashable {
        package let name: String
        /// The property attribute string (`T@"NSString",R,N`).
        package let attributes: String
    }

    package let offset: Int
    /// The name the Objective-C runtime registers: `_TtP<module><name>_` for
    /// a Swift protocol the source did not rename, the `@objc(Name)` name for
    /// one it did, the plain name for a protocol declared in Objective-C.
    package let runtimeName: String
    package let flags: UInt32
    /// The runtime names of the protocols this one inherits.
    package let inheritedProtocolRuntimeNames: [String]
    package let requiredInstanceMethods: [Method]
    package let requiredClassMethods: [Method]
    package let optionalInstanceMethods: [Method]
    package let optionalClassMethods: [Method]
    package let instanceProperties: [Property]
    package let classProperties: [Property]

    /// Bit 0 of the flags (`ProtocolDescriptorFlags::IsSwift`): the Swift
    /// compiler emitted this record. It says which compiler wrote the record,
    /// not which image defines the protocol: Swift emits a copy of every
    /// Swift `@objc` protocol an image references, and clang emits one with
    /// the bit clear when Objective-C code references a Swift protocol
    /// through a generated `-Swift.h` header. Only the low bits are the
    /// compiler's; the runtime and dyld set bits 29–31.
    package var isEmittedBySwift: Bool {
        flags & 1 != 0
    }

    /// Every method of the four lists, in the order the extended method
    /// types array follows.
    package var allMethods: [Method] {
        requiredInstanceMethods + requiredClassMethods + optionalInstanceMethods + optionalClassMethods
    }
}

// MARK: - Reading

extension ObjCProtocolRecord {
    /// Where `protocol_t` keeps the pointer to its extended method types.
    private static let extendedMethodTypesFieldOffset = MemoryLayout<ObjCProtocol64.Layout>.offset(of: \ObjCProtocol64.Layout._extendedMethodTypes)!

    /// The four method lists' entries before the extended types join them:
    /// required instance, required class, optional instance, optional class.
    typealias RawMethodLists = [[(selector: String, typeEncoding: String)]]

    static func make(
        offset: Int,
        runtimeName: String,
        flags: UInt32,
        recordSize: UInt32,
        inheritedProtocolRuntimeNames: [String],
        methodLists: RawMethodLists,
        instanceProperties: [Property],
        classProperties: [Property],
        in machO: some MachORepresentableWithCache & Readable
    ) -> ObjCProtocolRecord {
        let methodCount = methodLists.reduce(0) { $0 + $1.count }
        let extendedTypeEncodings = extendedMethodTypes(ofRecordAt: offset, recordSize: recordSize, methodCount: methodCount, in: machO)
        var slot = 0
        let lists: [[Method]] = methodLists.map { list in
            list.map { entry in
                defer { slot += 1 }
                return Method(selector: entry.selector, typeEncoding: entry.typeEncoding, extendedTypeEncoding: extendedTypeEncodings?[slot])
            }
        }
        return ObjCProtocolRecord(
            offset: offset,
            runtimeName: runtimeName,
            flags: flags,
            inheritedProtocolRuntimeNames: inheritedProtocolRuntimeNames,
            requiredInstanceMethods: lists[0],
            requiredClassMethods: lists[1],
            optionalInstanceMethods: lists[2],
            optionalClassMethods: lists[3],
            instanceProperties: instanceProperties,
            classProperties: classProperties
        )
    }

    /// The extended method types, one per method. MachOObjCSection's
    /// `extendedMethodTypes(in:)` reads only the array's first element, so
    /// the array is walked here. Each slot is a pointer like the field that
    /// leads to it, resolved through the reader's rebase in a file and read
    /// directly in process — the same path every absolute pointer of this
    /// library takes, in all three offset accountings. `nil` when the record
    /// is too short to carry the field, carries none, or a slot is null or
    /// unreadable: a partial array would misalign every later method.
    private static func extendedMethodTypes(ofRecordAt offset: Int, recordSize: UInt32, methodCount: Int, in machO: some MachORepresentableWithCache & Readable) -> [String]? {
        guard methodCount > 0, Int(recordSize) >= extendedMethodTypesFieldOffset + MemoryLayout<UInt64>.size else { return nil }
        let context = machO.context
        do {
            let arrayPointer = try RawPointer.resolve(at: context.addressFromOffset(offset + extendedMethodTypesFieldOffset), in: context)
            guard arrayPointer.address != 0 else { return nil }
            let arrayAddress = try arrayPointer.resolveAddress(in: context)
            var encodings: [String] = []
            encodings.reserveCapacity(methodCount)
            for index in 0 ..< methodCount {
                let slotAddress = context.advanceAddress(arrayAddress, by: index * MemoryLayout<UInt64>.size)
                let encodingPointer = try Pointer<String>.resolve(at: slotAddress, in: context)
                guard encodingPointer.address != 0 else { return nil }
                encodings.append(try encodingPointer.resolve(in: context))
            }
            return encodings
        } catch {
            return nil
        }
    }
}

extension MachOFile {
    /// `__objc_protolist`, every record read in full.
    func objcProtocolRecords() -> [ObjCProtocolRecord] {
        guard let objcProtocols = objc.protocols64 else { return [] }
        return objcProtocols.map { objcProtocolRecord(of: $0) }
    }

    private func objcProtocolRecord(of objcProtocol: ObjCProtocol64) -> ObjCProtocolRecord {
        let methodLists: ObjCProtocolRecord.RawMethodLists = [
            objcProtocol.instanceMethodList(in: self),
            objcProtocol.classMethodList(in: self),
            objcProtocol.optionalInstanceMethodList(in: self),
            objcProtocol.optionalClassMethodList(in: self),
        ].map { methodList in
            guard let methodList, !methodList.isListOfLists, let methods = methodList.methods(in: self) else { return [] }
            return methods.map { (selector: $0.name, typeEncoding: $0.types) }
        }
        var inheritedProtocolRuntimeNames: [String] = []
        if let protocolList = objcProtocol.protocolList(in: self), !protocolList.isListOfLists, let protocols = protocolList.protocols(in: self) {
            inheritedProtocolRuntimeNames = protocols.map { $1.mangledName(in: $0) }
        }
        return ObjCProtocolRecord.make(
            offset: objcProtocol.offset,
            runtimeName: objcProtocol.mangledName(in: self),
            flags: objcProtocol.flags,
            recordSize: objcProtocol.size,
            inheritedProtocolRuntimeNames: inheritedProtocolRuntimeNames,
            methodLists: methodLists,
            instanceProperties: properties(of: objcProtocol.instancePropertyList(in: self)),
            classProperties: properties(of: objcProtocol.classPropertyList(in: self)),
            in: self
        )
    }

    private func properties(of propertyList: ObjCPropertyList?) -> [ObjCProtocolRecord.Property] {
        guard let propertyList, !propertyList.isListOfLists else { return [] }
        return propertyList.properties(in: self).map { .init(name: $0.name, attributes: $0.attributes) }
    }
}

extension MachOImage {
    /// `__objc_protolist`, every record read in full.
    func objcProtocolRecords() -> [ObjCProtocolRecord] {
        guard let objcProtocols = objc.protocols64 else { return [] }
        return objcProtocols.map { objcProtocolRecord(of: $0) }
    }

    private func objcProtocolRecord(of objcProtocol: ObjCProtocol64) -> ObjCProtocolRecord {
        let methodLists: ObjCProtocolRecord.RawMethodLists = [
            objcProtocol.instanceMethodList(in: self),
            objcProtocol.classMethodList(in: self),
            objcProtocol.optionalInstanceMethodList(in: self),
            objcProtocol.optionalClassMethodList(in: self),
        ].map { methodList in
            guard let methodList, !methodList.isListOfLists else { return [] }
            return methodList.methods(in: self).map { (selector: $0.name, typeEncoding: $0.types) }
        }
        var inheritedProtocolRuntimeNames: [String] = []
        if let protocolList = objcProtocol.protocolList(in: self), !protocolList.isListOfLists, let protocols = protocolList.protocols(in: self) {
            inheritedProtocolRuntimeNames = protocols.map { $1.mangledName(in: $0) }
        }
        return ObjCProtocolRecord.make(
            offset: objcProtocol.offset,
            runtimeName: objcProtocol.mangledName(in: self),
            flags: objcProtocol.flags,
            recordSize: objcProtocol.size,
            inheritedProtocolRuntimeNames: inheritedProtocolRuntimeNames,
            methodLists: methodLists,
            instanceProperties: properties(of: objcProtocol.instancePropertyList(in: self)),
            classProperties: properties(of: objcProtocol.classPropertyList(in: self)),
            in: self
        )
    }

    private func properties(of propertyList: ObjCPropertyList?) -> [ObjCProtocolRecord.Property] {
        guard let propertyList, !propertyList.isListOfLists else { return [] }
        return propertyList.properties(in: self).map { .init(name: $0.name, attributes: $0.attributes) }
    }
}
