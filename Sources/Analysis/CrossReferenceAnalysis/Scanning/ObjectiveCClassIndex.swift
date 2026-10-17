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

    /// User-space addresses fit in 47 bits; above them are pointer
    /// authentication bits.
    private static let addressMask: UInt64 = 0x0000_7FFF_FFFF_FFFF

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
                let classAddress = UInt(list.loadUnaligned(fromByteOffset: position * 8, as: UInt64.self) & Self.addressMask)
                guard let classObject = UnsafeRawPointer(bitPattern: classAddress) else { continue }
                entries[classAddress] = Entry(classAddress: classAddress, isMetaclass: false)
                // A class's `isa` is its metaclass.
                let metaclassAddress = UInt(classObject.loadUnaligned(as: UInt64.self) & Self.addressMask)
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

    /// The unslid addresses of the class at `classLocation` and of its
    /// metaclass.
    func objectAddresses(ofClassAt classLocation: CodeLocation) -> [UInt64] {
        let classAddress = UInt(bitPattern: Int(bitPattern: UInt(classLocation.address)) &+ slide)
        return entriesByRuntimeAddress.compactMap { address, entry in
            entry.classAddress == classAddress ? location(ofRuntimeAddress: address).address : nil
        }
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
