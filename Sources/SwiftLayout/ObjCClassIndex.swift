import MachOKit
@_spi(Core) import MachOObjCSection

/// Builds a per-image index from an Objective-C class's bare name to the start
/// layout a Swift subclass inherits from it: the class's `instanceSize` (where a
/// subclass's first stored property begins) and a pointer-aligned start
/// alignment.
///
/// `instanceSize` — not `instanceStart` — is the value the runtime uses to
/// position a Swift subclass's fields. `instanceStart` is where the ObjC class's
/// *own* first ivar begins (i.e. its own superclass's size) and is left `0` in
/// the on-disk shared cache, so it must not be used here. The size is read from
/// the class's *instance* `class_ro_t`, resolving the realized (`class_rw_t`)
/// form for classes dyld has already realized in-process — the same read-only
/// data the runtime's reflection lowers through, so the value equals
/// `ObjCClass.info(in:).instanceSize` without parsing methods/ivars/protocols.
///
/// `objc.classes64` and the ro/rw accessors are concrete `MachOFile` /
/// `MachOImage` overloads (not protocol-generic), so the two readers need
/// separate builders — mirroring how `ImageUniverse+DependencyClosure` splits
/// the in-process and offline closure factories.
enum ObjCClassIndex {
    /// The start alignment a Swift class inherits from an Objective-C ancestor:
    /// ObjC instances are pointer-aligned (8 bytes on 64-bit). The per-field
    /// alignment in `accumulateFieldLayout` raises the aggregate alignment
    /// further as needed; this only seeds its minimum.
    static let inheritedAlignmentMask = 7

    /// Bare class name → (instanceSize, alignmentMask) for every Objective-C
    /// class in an in-process image, first writer wins on duplicate names. An
    /// image with no `__objc_classlist` contributes nothing.
    static func instanceSizesByBareName(in machO: MachOImage) -> [String: (instanceSize: Int, alignmentMask: Int)] {
        guard let objCClasses = machO.objc.classes64 else { return [:] }
        var instanceSizesByBareName: [String: (instanceSize: Int, alignmentMask: Int)] = [:]
        for objCClass in objCClasses {
            guard
                let readOnlyData = instanceReadOnlyData(of: objCClass, in: machO),
                let className = readOnlyData.name(in: machO), !className.isEmpty,
                instanceSizesByBareName[className] == nil
            else { continue }
            instanceSizesByBareName[className] = (Int(readOnlyData.layout.instanceSize), inheritedAlignmentMask)
        }
        return instanceSizesByBareName
    }

    /// Bare class name → (instanceSize, alignmentMask) for every Objective-C
    /// class in a file-backed (or dyld-cache-resident) image. On disk a class's
    /// `data` pointer points straight at `class_ro_t` (realization happens only
    /// at runtime), so the read-only data reads directly.
    static func instanceSizesByBareName(in machO: MachOFile) -> [String: (instanceSize: Int, alignmentMask: Int)] {
        guard let objCClasses = machO.objc.classes64 else { return [:] }
        var instanceSizesByBareName: [String: (instanceSize: Int, alignmentMask: Int)] = [:]
        for objCClass in objCClasses {
            guard
                let readOnlyData = objCClass.classROData(in: machO),
                let className = readOnlyData.name(in: machO), !className.isEmpty,
                instanceSizesByBareName[className] == nil
            else { continue }
            instanceSizesByBareName[className] = (Int(readOnlyData.layout.instanceSize), inheritedAlignmentMask)
        }
        return instanceSizesByBareName
    }

    /// The instance `class_ro_t` of an in-process ObjC class, resolving the
    /// realized (`class_rw_t`) form dyld installs for cache-resident classes
    /// (whose `data` pointer then points at `class_rw_t`, not `class_ro_t`).
    /// Ports the runtime reflection's instance-ro lookup (`ObjCDump.data(in:)`)
    /// without the metaclass it does not need here.
    private static func instanceReadOnlyData(of objCClass: ObjCClass64, in machO: MachOImage) -> ObjCClassROData64? {
        if let readOnlyData = objCClass.classROData(in: machO) { return readOnlyData }
        guard let readWriteData = objCClass.classRWData(in: machO) else { return nil }
        if let readOnlyData = readWriteData.classROData(in: machO) { return readOnlyData }
        return readWriteData.ext(in: machO)?.classROData(in: machO)
    }
}
