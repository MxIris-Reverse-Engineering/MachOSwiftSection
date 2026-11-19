import Foundation
import MachOKit
@_spi(Core) import MachOObjCSection
@_spi(Internals) import MachOCodeReferences

/// A class object a scan met: its class's runtime name, and where the class
/// lies. A metaclass is met as its class.
package struct ObjectiveCClassObject: Hashable, Sendable {
    package let name: String
    package let location: CodeLocation
}

/// The class objects one image defines, by address: every class of its
/// `__objc_classlist` and its metaclass.
///
/// How a scan tells a class reference from any other pointer. A class object
/// cannot be recognized by the section it lies in — 92,000 Swift classes and
/// metaclasses of the macOS 27.2 cache sit in `__data`, not `__objc_data` —
/// so a value counts as a class only when its image lists it. Built per image
/// on first use, straight from the class list: going through
/// `MachOImage.objc.classes64` looks up the image's load commands again for
/// every class, which made a scan of the whole cache twice as slow. A
/// class's name is read only once a reference to it is reported.
package final class ObjectiveCClassIndex: @unchecked Sendable {
    private struct Entry {
        /// The class's own runtime address; a metaclass's entry holds its
        /// class's.
        let classAddress: UInt
        let isMetaclass: Bool
    }

    private let image: CodeImage
    private let imageIndex: Int
    private let memory: any CrossReferenceMemory
    private let slide: Int
    private let entriesByRuntimeAddress: [UInt: Entry]
    private let lock = NSLock()
    private var namesByClassAddress: [UInt: String?] = [:]

    package init(image: CodeImage, imageIndex: Int, memory: any CrossReferenceMemory) {
        self.image = image
        self.imageIndex = imageIndex
        self.memory = memory
        self.slide = image.slide
        var entries: [UInt: Entry] = [:]
        for section in image.reader.sections64 where section.sectionName == "__objc_classlist" {
            let list = UInt(bitPattern: Int(bitPattern: UInt(section.address)) &+ slide)
            for position in 0 ..< section.size / 8 {
                guard let classAddress = memory.pointer(at: list &+ UInt(position * 8)), classAddress != 0 else { continue }
                entries[classAddress] = Entry(classAddress: classAddress, isMetaclass: false)
                // A class's `isa` is its metaclass.
                guard let metaclassAddress = memory.pointer(at: classAddress) else { continue }
                if metaclassAddress != 0, entries[metaclassAddress] == nil {
                    entries[metaclassAddress] = Entry(classAddress: classAddress, isMetaclass: true)
                }
            }
        }
        self.entriesByRuntimeAddress = entries
    }

    /// The class object at the runtime `address`, a metaclass as its class.
    package func classObject(atRuntimeAddress address: UInt) -> ObjectiveCClassObject? {
        guard let entry = entriesByRuntimeAddress[address], let name = name(ofClassAt: entry.classAddress) else { return nil }
        return ObjectiveCClassObject(name: name, location: location(ofRuntimeAddress: entry.classAddress))
    }

    /// Where the classes named `name` lie; reads every class's name once.
    package func classLocations(named name: String) -> [CodeLocation] {
        entriesByRuntimeAddress.compactMap { address, entry in
            !entry.isMetaclass && self.name(ofClassAt: address) == name ? location(ofRuntimeAddress: address) : nil
        }
    }

    /// Reads every class's name now, which the first ``classLocations(named:)``
    /// would.
    package func readEveryName() {
        for (address, entry) in entriesByRuntimeAddress where !entry.isMetaclass {
            _ = name(ofClassAt: address)
        }
    }

    /// Whether every class's name has been read; for tests.
    package var hasReadEveryName: Bool {
        let classCount = entriesByRuntimeAddress.values.count { !$0.isMetaclass }
        lock.lock()
        defer { lock.unlock() }
        return namesByClassAddress.count >= classCount
    }

    /// The memory the index takes, with the names read; see `ApproximateSize`.
    package var approximateByteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return namesByClassAddress.values.reduce(ApproximateSize.of(entriesByRuntimeAddress) + ApproximateSize.of(namesByClassAddress)) { $0 + ($1.map(ApproximateSize.of) ?? 0) }
    }

    /// The unslid addresses of the class at `classLocation` and of its
    /// metaclass.
    package func objectAddresses(ofClassAt classLocation: CodeLocation) -> [UInt64] {
        let classAddress = UInt(bitPattern: Int(bitPattern: UInt(classLocation.address)) &+ slide)
        return entriesByRuntimeAddress.compactMap { address, entry in
            entry.classAddress == classAddress ? location(ofRuntimeAddress: address).address : nil
        }
    }

    /// Whether the class at `classLocation` is a Swift class: one of the two
    /// low bits of its data word (+0x20) is set.
    package func isSwiftClass(at classLocation: CodeLocation) -> Bool {
        let classAddress = UInt(bitPattern: Int(bitPattern: UInt(classLocation.address)) &+ slide)
        guard entriesByRuntimeAddress[classAddress] != nil, let dataWord = memory.load(UInt64.self, at: classAddress &+ 0x20) else { return false }
        return dataWord & 0x3 != 0
    }

    /// The Swift class whose type context descriptor lies at the runtime
    /// `descriptor`: a Swift class object holds its descriptor at +0x40, and
    /// sets one of the two low bits of its data word (+0x20).
    package func swiftClassObject(describedBy descriptor: UInt) -> ObjectiveCClassObject? {
        for (address, entry) in entriesByRuntimeAddress where !entry.isMetaclass {
            guard let dataWord = memory.load(UInt64.self, at: address &+ 0x20),
                  dataWord & 0x3 != 0,
                  memory.pointer(at: address &+ 0x40) == descriptor,
                  let name = name(ofClassAt: address)
            else { continue }
            return ObjectiveCClassObject(name: name, location: location(ofRuntimeAddress: address))
        }
        return nil
    }

    private func location(ofRuntimeAddress address: UInt) -> CodeLocation {
        CodeLocation(imageIndex: imageIndex, address: UInt64(bitPattern: Int64(bitPattern: UInt64(address)) &- Int64(slide)))
    }

    private func name(ofClassAt classAddress: UInt) -> String? {
        lock.lock()
        if let known = namesByClassAddress[classAddress] {
            lock.unlock()
            return known
        }
        lock.unlock()
        var name: String?
        // The class object as MachOObjCSection reads it: its bytes as they
        // stand — in a file, its pointers still fixups — at the offset the
        // reader counts in.
        if let layout = memory.load(ObjCClass64.Layout.self, at: classAddress) {
            if let machOImage = image.reader.asMachOImage {
                let classObject = ObjCClass64(layout: layout, offset: Int(bitPattern: classAddress &- UInt(bitPattern: machOImage.ptr)))
                name = Self.readOnlyData(of: classObject, in: machOImage)?.name(in: machOImage)
            } else if let machOFile = image.reader.asMachOFile, let offset = image.readerOffset(ofUnslidAddress: image.unslidAddress(ofRuntime: classAddress)) {
                // A class in a file is never realized: its data is read-only.
                name = ObjCClass64(layout: layout, offset: offset).classROData(in: machOFile)?.name(in: machOFile)
            }
        }
        lock.lock()
        namesByClassAddress[classAddress] = name
        lock.unlock()
        return name
    }

    /// A class's read-only data, through its read-write data once the
    /// runtime has realized it — as for every class an image loaded in this
    /// process has used.
    package static func readOnlyData(of classObject: ObjCClass64, in image: MachOImage) -> ObjCClassROData64? {
        if let readOnlyData = classObject.classROData(in: image) { return readOnlyData }
        guard let readWriteData = classObject.classRWData(in: image) else { return nil }
        if let readOnlyData = readWriteData.classROData(in: image) { return readOnlyData }
        return readWriteData.ext(in: image)?.classROData(in: image)
    }
}
