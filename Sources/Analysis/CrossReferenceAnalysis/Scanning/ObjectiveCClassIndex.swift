import Foundation
import MachOKit
@_spi(Core) import MachOObjCSection

/// A class object a scan met: its class's runtime name, and where the class
/// lies. A metaclass is met as its class.
struct ObjectiveCClassObject: Hashable {
    let name: String
    let location: CodeLocation
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
final class ObjectiveCClassIndex: @unchecked Sendable {
    private struct Entry {
        /// The class's own runtime address; a metaclass's entry holds its
        /// class's.
        let classAddress: UInt
        let isMetaclass: Bool
    }

    private let image: MachOImage
    private let imageIndex: Int
    private let slide: Int
    private let entriesByRuntimeAddress: [UInt: Entry]
    private let lock = NSLock()
    private var namesByClassAddress: [UInt: String?] = [:]

    init(image: MachOImage, imageIndex: Int) {
        self.image = image
        self.imageIndex = imageIndex
        self.slide = image.vmaddrSlide ?? 0
        var entries: [UInt: Entry] = [:]
        for section in image.sections64 where section.sectionName == "__objc_classlist" {
            guard let list = UnsafeRawPointer(bitPattern: Int(bitPattern: UInt(section.address)) &+ slide) else { continue }
            for position in 0 ..< section.size / 8 {
                let classAddress = StoredPointer.address(in: list.loadUnaligned(fromByteOffset: position * 8, as: UInt64.self))
                guard let classObject = UnsafeRawPointer(bitPattern: classAddress) else { continue }
                entries[classAddress] = Entry(classAddress: classAddress, isMetaclass: false)
                // A class's `isa` is its metaclass.
                let metaclassAddress = StoredPointer.address(in: classObject.loadUnaligned(as: UInt64.self))
                if metaclassAddress != 0, entries[metaclassAddress] == nil {
                    entries[metaclassAddress] = Entry(classAddress: classAddress, isMetaclass: true)
                }
            }
        }
        self.entriesByRuntimeAddress = entries
    }

    /// The class object at the runtime `address`, a metaclass as its class.
    func classObject(atRuntimeAddress address: UInt) -> ObjectiveCClassObject? {
        guard let entry = entriesByRuntimeAddress[address], let name = name(ofClassAt: entry.classAddress) else { return nil }
        return ObjectiveCClassObject(name: name, location: location(ofRuntimeAddress: entry.classAddress))
    }

    /// Where the classes named `name` lie; reads every class's name once.
    func classLocations(named name: String) -> [CodeLocation] {
        entriesByRuntimeAddress.compactMap { address, entry in
            !entry.isMetaclass && self.name(ofClassAt: address) == name ? location(ofRuntimeAddress: address) : nil
        }
    }

    /// Reads every class's name now, which the first ``classLocations(named:)``
    /// would.
    func readEveryName() {
        for (address, entry) in entriesByRuntimeAddress where !entry.isMetaclass {
            _ = name(ofClassAt: address)
        }
    }

    /// Whether every class's name has been read; for tests.
    var hasReadEveryName: Bool {
        let classCount = entriesByRuntimeAddress.values.count { !$0.isMetaclass }
        lock.lock()
        defer { lock.unlock() }
        return namesByClassAddress.count >= classCount
    }

    /// The memory the index takes, with the names read; see `ApproximateSize`.
    var approximateByteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return namesByClassAddress.values.reduce(ApproximateSize.of(entriesByRuntimeAddress) + ApproximateSize.of(namesByClassAddress)) { $0 + ($1.map(ApproximateSize.of) ?? 0) }
    }

    /// The unslid addresses of the class at `classLocation` and of its
    /// metaclass.
    func objectAddresses(ofClassAt classLocation: CodeLocation) -> [UInt64] {
        let classAddress = UInt(bitPattern: Int(bitPattern: UInt(classLocation.address)) &+ slide)
        return entriesByRuntimeAddress.compactMap { address, entry in
            entry.classAddress == classAddress ? location(ofRuntimeAddress: address).address : nil
        }
    }

    /// Whether the class at `classLocation` is a Swift class: one of the two
    /// low bits of its data word (+0x20) is set.
    func isSwiftClass(at classLocation: CodeLocation) -> Bool {
        let classAddress = UInt(bitPattern: Int(bitPattern: UInt(classLocation.address)) &+ slide)
        guard entriesByRuntimeAddress[classAddress] != nil, let classObject = UnsafeRawPointer(bitPattern: classAddress) else { return false }
        return classObject.loadUnaligned(fromByteOffset: 0x20, as: UInt64.self) & 0x3 != 0
    }

    /// The Swift class whose type context descriptor lies at the runtime
    /// `descriptor`: a Swift class object holds its descriptor at +0x40, and
    /// sets one of the two low bits of its data word (+0x20).
    func swiftClassObject(describedBy descriptor: UInt) -> ObjectiveCClassObject? {
        for (address, entry) in entriesByRuntimeAddress where !entry.isMetaclass {
            guard let classObject = UnsafeRawPointer(bitPattern: address),
                  classObject.loadUnaligned(fromByteOffset: 0x20, as: UInt64.self) & 0x3 != 0,
                  StoredPointer.address(in: classObject.loadUnaligned(fromByteOffset: 0x40, as: UInt64.self)) == descriptor,
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
        if let pointer = UnsafeRawPointer(bitPattern: classAddress) {
            let classObject = ObjCClass64(
                layout: pointer.assumingMemoryBound(to: ObjCClass64.Layout.self).pointee,
                offset: Int(bitPattern: classAddress &- UInt(bitPattern: image.ptr))
            )
            name = Self.readOnlyData(of: classObject, in: image)?.name(in: image)
        }
        lock.lock()
        namesByClassAddress[classAddress] = name
        lock.unlock()
        return name
    }

    /// A class's read-only data, through its read-write data once the
    /// runtime has realized it — as for every class an image loaded in this
    /// process has used.
    static func readOnlyData(of classObject: ObjCClass64, in image: MachOImage) -> ObjCClassROData64? {
        if let readOnlyData = classObject.classROData(in: image) { return readOnlyData }
        guard let readWriteData = classObject.classRWData(in: image) else { return nil }
        if let readOnlyData = readWriteData.classROData(in: image) { return readOnlyData }
        return readWriteData.ext(in: image)?.classROData(in: image)
    }
}
