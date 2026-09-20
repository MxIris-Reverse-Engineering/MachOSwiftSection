import Foundation
import FoundationToolbox
import MachOKit
import MachOKitExtensions
@_spi(Core) import MachOObjCSection
@_spi(Internals) import MachOCaches
import MachOReading

/// The library's own ``ObjCClassHierarchy`` reader (evolution proposal
/// `objc-ancestor-override-recovery`): the fallback behind
/// ``ObjCClassHierarchyProviderStore`` for an image no host registered a
/// provider for.
///
/// Per image, the eager part is one pass over `__objc_classlist` reading only
/// each class object's `class_ro_t` name — the ObjC runtime name → class
/// object table, and for Swift classes the qualified-name → runtime-name
/// table the Swift side needs to ask by (a `TypeDefinition` knows its
/// qualified name, the ObjC side files the class under `_TtC…`). Method lists
/// are NOT read here: they are read per class on demand and memoized, so an
/// image's clang classes cost nothing and NSView's two thousand selectors are
/// read once for AppKit's 173 Swift subclasses. An ancestor in another image
/// memoizes in THAT image's storage — AppKit's and SwiftUI's classes share
/// libobjc's `NSObject` — and the memo is keyed by the class object's offset,
/// so it survives the ObjC reader minting a fresh `MachOFile` per superclass
/// hop (identifiers are UUID-keyed, so the shared cache finds the same entry).
///
/// Cache images and in-process images follow their superclass into other
/// images; a standalone file whose superclass is a bind stops there and says
/// so (`isAncestorChainComplete == false`).
@Loggable(.private, subsystem: "com.machoswiftsection.swift-inspection", category: "ObjCClassMethodIndex")
package final class ObjCClassMethodIndex: SharedCache<ObjCClassMethodIndex.Storage>, @unchecked Sendable {
    package static let shared = ObjCClassMethodIndex()

    /// One ancestor's selector sets, memoized per class object.
    struct SelectorSets {
        let className: String
        let instanceSelectors: Set<String>
        let classSelectors: Set<String>
    }

    package final class Storage: @unchecked Sendable {
        /// `class_ro_t` name → class object, every class the image defines.
        let classObjectsByRuntimeName: [String: ObjCClass64]

        /// Swift qualified name → runtime names. More than one entry means
        /// same-named private classes from different files; the lookup then
        /// refuses to guess.
        let runtimeNamesBySwiftQualifiedName: [String: [String]]

        private let lock = NSLock()
        private var selectorSetsByClassOffset: [Int: SelectorSets] = [:]
        private var hierarchiesByClassOffset: [Int: ObjCClassHierarchy] = [:]

        init(classObjectsByRuntimeName: [String: ObjCClass64], runtimeNamesBySwiftQualifiedName: [String: [String]]) {
            self.classObjectsByRuntimeName = classObjectsByRuntimeName
            self.runtimeNamesBySwiftQualifiedName = runtimeNamesBySwiftQualifiedName
        }

        fileprivate func memoizedSelectorSets(forClassOffset offset: Int) -> SelectorSets? {
            lock.lock()
            defer { lock.unlock() }
            return selectorSetsByClassOffset[offset]
        }

        fileprivate func memoize(_ selectorSets: SelectorSets, forClassOffset offset: Int) {
            lock.lock()
            defer { lock.unlock() }
            selectorSetsByClassOffset[offset] = selectorSets
        }

        fileprivate func memoizedHierarchy(forClassOffset offset: Int) -> ObjCClassHierarchy? {
            lock.lock()
            defer { lock.unlock() }
            return hierarchiesByClassOffset[offset]
        }

        fileprivate func memoize(_ hierarchy: ObjCClassHierarchy, forClassOffset offset: Int) {
            lock.lock()
            defer { lock.unlock() }
            hierarchiesByClassOffset[offset] = hierarchy
        }
    }

    override package func buildStorage(for machO: some MachORepresentableWithCache) -> Storage? {
        if let machOFile = machO as? MachOFile {
            return Self.build(in: machOFile)
        } else if let machOImage = machO as? MachOImage {
            return Self.build(in: machOImage)
        }
        return nil
    }

    // MARK: - Queries

    /// The runtime names of the Swift classes whose qualified name is
    /// `qualifiedName`; empty when the image defines no such class object
    /// (a generic class has none — it is instantiated at runtime).
    package func runtimeNames(forSwiftClassQualifiedName qualifiedName: String, in machO: some MachORepresentableWithCache) -> [String] {
        storage(in: machO)?.runtimeNamesBySwiftQualifiedName[qualifiedName] ?? []
    }

    /// The hierarchy of the class the image defines under `runtimeName`, or
    /// `nil` when there is no such class object or it has no ObjC method of
    /// its own (nothing to attribute — the ancestor walk is skipped).
    package func hierarchy(forRuntimeName runtimeName: String, in machO: some MachORepresentableWithCache) -> ObjCClassHierarchy? {
        if let machOFile = machO as? MachOFile {
            return hierarchy(forRuntimeName: runtimeName, reader: machOFile)
        } else if let machOImage = machO as? MachOImage {
            return hierarchy(forRuntimeName: runtimeName, reader: machOImage)
        }
        return nil
    }

    private func hierarchy(forRuntimeName runtimeName: String, reader: some ObjCImplementationClassReading) -> ObjCClassHierarchy? {
        guard let storage = storage(in: reader), let classObject = storage.classObjectsByRuntimeName[runtimeName] else { return nil }
        if let memoized = storage.memoizedHierarchy(forClassOffset: classObject.offset) {
            return memoized
        }
        // Computed OUTSIDE the storage lock: the ancestor walk memoizes into
        // the same storage when an ancestor lives in this image.
        guard let readOnlyData = reader.instanceReadOnlyData(of: classObject) else { return nil }
        var methods: [ObjCClassHierarchy.Method] = reader.methods(of: readOnlyData).map {
            ObjCClassHierarchy.Method(selector: $0.selector, isClassMethod: false, implementation: $0.implementationOffset.map { .offset($0) })
        }
        if let metaClass = reader.metaClass(of: classObject), let metaReadOnlyData = reader.instanceReadOnlyData(of: metaClass) {
            methods += reader.methods(of: metaReadOnlyData).map {
                ObjCClassHierarchy.Method(selector: $0.selector, isClassMethod: true, implementation: $0.implementationOffset.map { .offset($0) })
            }
        }
        guard !methods.isEmpty else { return nil }

        var ancestors: [ObjCClassHierarchy.Ancestor] = []
        var isAncestorChainComplete = true
        var unresolvedAncestorName: String?
        var location = reader.superclassLocation(of: classObject)
        var hopCount = 0
        walk: while true {
            switch location {
            case .root:
                break walk
            case .unresolvable(let superclassName):
                isAncestorChainComplete = false
                unresolvedAncestorName = superclassName
                break walk
            case .resolved(let ancestorReader, let ancestorClassObject):
                hopCount += 1
                guard hopCount <= 64 else {
                    // A superclass cycle is corrupt metadata; refuse to spin.
                    #log(.error, "superclass chain of \(runtimeName, privacy: .public) exceeds 64 hops; treating it as broken")
                    isAncestorChainComplete = false
                    break walk
                }
                guard let selectorSets = selectorSets(of: ancestorClassObject, in: ancestorReader) else {
                    isAncestorChainComplete = false
                    break walk
                }
                ancestors.append(ObjCClassHierarchy.Ancestor(className: selectorSets.className, instanceSelectors: selectorSets.instanceSelectors, classSelectors: selectorSets.classSelectors))
                location = ancestorReader.superclassLocation(of: ancestorClassObject)
            }
        }

        let hierarchy = ObjCClassHierarchy(className: runtimeName, methods: methods, ancestors: ancestors, isAncestorChainComplete: isAncestorChainComplete, unresolvedAncestorName: unresolvedAncestorName)
        storage.memoize(hierarchy, forClassOffset: classObject.offset)
        return hierarchy
    }

    /// The selectors `classObject` (living in `reader`'s image) implements,
    /// memoized in that image's storage.
    private func selectorSets(of classObject: ObjCClass64, in reader: any ObjCImplementationClassReading) -> SelectorSets? {
        func compute<Reader: ObjCImplementationClassReading>(in reader: Reader) -> SelectorSets? {
            guard let storage = storage(in: reader) else { return nil }
            if let memoized = storage.memoizedSelectorSets(forClassOffset: classObject.offset) {
                return memoized
            }
            guard let readOnlyData = reader.instanceReadOnlyData(of: classObject), let className = reader.className(of: readOnlyData) else { return nil }
            let instanceSelectors = Set(reader.methods(of: readOnlyData).map(\.selector))
            var classSelectors: Set<String> = []
            if let metaClass = reader.metaClass(of: classObject), let metaReadOnlyData = reader.instanceReadOnlyData(of: metaClass) {
                classSelectors = Set(reader.methods(of: metaReadOnlyData).map(\.selector))
            }
            let selectorSets = SelectorSets(className: className, instanceSelectors: instanceSelectors, classSelectors: classSelectors)
            storage.memoize(selectorSets, forClassOffset: classObject.offset)
            return selectorSets
        }
        return compute(in: reader)
    }

    // MARK: - Build

    private static func build(in machO: some ObjCImplementationClassReading) -> Storage {
        guard let classObjects = machO.objcImplementationClassObjects() else {
            return Storage(classObjectsByRuntimeName: [:], runtimeNamesBySwiftQualifiedName: [:])
        }
        var classObjectsByRuntimeName: [String: ObjCClass64] = [:]
        var runtimeNamesBySwiftQualifiedName: [String: [String]] = [:]
        for classObject in classObjects {
            guard let readOnlyData = machO.instanceReadOnlyData(of: classObject), !readOnlyData.isMetaClass,
                  let runtimeName = machO.className(of: readOnlyData), !runtimeName.isEmpty,
                  classObjectsByRuntimeName[runtimeName] == nil
            else { continue }
            classObjectsByRuntimeName[runtimeName] = classObject
            if classObject.isSwift, let qualifiedName = NodeTypeNaming.swiftClassQualifiedName(fromRuntimeName: runtimeName) {
                runtimeNamesBySwiftQualifiedName[qualifiedName, default: []].append(runtimeName)
            }
        }
        return Storage(classObjectsByRuntimeName: classObjectsByRuntimeName, runtimeNamesBySwiftQualifiedName: runtimeNamesBySwiftQualifiedName)
    }
}

/// Where a class's superclass pointer leads.
enum ObjCSuperclassLocation {
    /// The class is a root class (null superclass).
    case root
    /// The superclass, paired with the reader for the image it lives in —
    /// the same image, or another image of the same cache / process.
    case resolved(any ObjCImplementationClassReading, ObjCClass64)
    /// The superclass pointer is a bind into an image this reader cannot
    /// reach (a standalone file's dependency); `String?` is the bound
    /// symbol's class name when the bind names one.
    case unresolvable(String?)
}
