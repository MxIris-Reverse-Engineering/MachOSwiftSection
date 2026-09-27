import Foundation
import FoundationToolbox
import MachOKit
import MachOKitExtensions
import MachOReading
import MachOSwiftSection
import Demangling
@_spi(Core) import MachOObjCSection
@_spi(Internals) import MachOCaches

/// Per-image index of the Swift classes whose source renamed them for the
/// Objective-C runtime — `@objc(Name)` or `@_objcRuntimeName(Name)` —
/// (evolution proposal `objc-custom-class-name`), keyed by the class's
/// nominal type descriptor.
///
/// The join goes through the class METADATA, never through the name. The
/// ObjC-side indexes find a Swift class by demangling its `class_ro_t` name,
/// and a renamed class's name is no longer the `_TtC…` mangling that
/// demangles to anything — which is why those indexes never matched such a
/// class. Two routes cover every class that can carry the attribute:
///
/// - A class whose metadata is emitted statically (the Fixed, FixedOrUpdate
///   and Update strategies) is in `__objc_classlist`, and its class object IS
///   its Swift metadata — the address points coincide. The flag word and the
///   nominal type descriptor pointer are read straight off it. That pointer
///   is absolute: a rebase or chained fixup in a file, signed on arm64e, so
///   it is read through its own field (`Pointer.resolve(from:in:)` resolves
///   the rebase first); `descriptor(in:)` would take the undecoded value a
///   cache image stores.
/// - A non-generic class with a superclass in another resilience domain (the
///   Resilient strategy) is instantiated at runtime and has no class object
///   in the list. Its descriptor's singleton metadata initialization points
///   at a ``ResilientClassMetadataPattern`` carrying the same flag word and a
///   relative pointer to the `class_ro_t` template.
///
/// Generic classes and non-generic classes with generic ancestry (the
/// Singleton strategy) cannot be renamed — the compiler rejects `@objc(Name)`
/// on them — so neither route looks for them.
///
/// Only renamed classes are recorded: the flag word is read for every Swift
/// class object, the descriptor and the name only for the ones whose
/// `HasCustomObjCName` bit is set. Built once per image, lazily, through the
/// shared-cache machinery — the name-keyed indexes consult it only when a
/// Swift-class lookup misses, so an image that is merely an ObjC ancestor
/// never builds one — and evicted with the other ObjC-side per-image state
/// (`ObjCClassHierarchies.removeCache(for:)`). This module sits below the
/// event layer, so a class that could not be read is only logged.
@Loggable(.private, subsystem: "com.machoswiftsection.swift-inspection", category: "SwiftClassObjectIndex")
package final class SwiftClassObjectIndex: SharedCache<SwiftClassObjectIndex.Storage>, @unchecked Sendable {
    package static let shared = SwiftClassObjectIndex()

    private override init() {
        super.init()
    }

    /// One renamed class.
    struct RenamedClass {
        let customObjCClassName: CustomObjCClassName
        /// The class object's own `class_ro_t.instanceStart`; `nil` for a class
        /// without one in the class list (a resilient superclass), which the
        /// Swift runtime lays out itself.
        let instanceStart: Int?
    }

    package final class Storage: @unchecked Sendable {
        let renamedClassesByDescriptorOffset: [Int: RenamedClass]

        /// Swift qualified name (`AppKit.NSScrollPocket`) → runtime names, for
        /// the renamed classes with a class object: the key the ObjC-side
        /// indexes derive by demangling a `_TtC…` runtime name, which a name
        /// the source chose does not yield. More than one entry means
        /// same-named private classes, as in those indexes.
        let customRuntimeNamesBySwiftQualifiedName: [String: [String]]

        init(renamedClassesByDescriptorOffset: [Int: RenamedClass], customRuntimeNamesBySwiftQualifiedName: [String: [String]]) {
            self.renamedClassesByDescriptorOffset = renamedClassesByDescriptorOffset
            self.customRuntimeNamesBySwiftQualifiedName = customRuntimeNamesBySwiftQualifiedName
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

    /// The runtime name the source gave the class whose nominal type
    /// descriptor sits at `descriptorOffset`, or `nil` when it has none.
    package func customObjCClassName(forClassDescriptorOffset descriptorOffset: Int, in machO: some MachORepresentableWithCache) -> CustomObjCClassName? {
        storage(in: machO)?.renamedClassesByDescriptorOffset[descriptorOffset]?.customObjCClassName
    }

    /// The own `class_ro_t.instanceStart` of the renamed class whose nominal
    /// type descriptor sits at `descriptorOffset` — the fact the static
    /// layout engine keys by a qualified name demangled from the runtime
    /// name — or `nil` when the class is not renamed or has no class object.
    package func renamedClassInstanceStart(forClassDescriptorOffset descriptorOffset: Int, in machO: some MachORepresentableWithCache) -> Int? {
        storage(in: machO)?.renamedClassesByDescriptorOffset[descriptorOffset]?.instanceStart
    }

    /// The runtime names of the renamed classes whose Swift qualified name is
    /// `qualifiedName`; empty when there is none. The fallback of a
    /// name-keyed lookup that missed: a `_TtC…` class is found by demangling.
    package func customRuntimeNames(forSwiftClassQualifiedName qualifiedName: String, in machO: some MachORepresentableWithCache) -> [String] {
        storage(in: machO)?.customRuntimeNamesBySwiftQualifiedName[qualifiedName] ?? []
    }

    // MARK: - Build

    /// `IsStaticSpecialization | IsCanonicalStaticSpecialization`: metadata
    /// the compiler prespecialized for one instantiation of a generic class.
    /// It can sit in the class list, but a generic class cannot be renamed.
    private static let staticSpecializationClassFlags: UInt32 = ClassFlags.isStaticSpecialization.rawValue | ClassFlags.isCanonicalStaticSpecialization.rawValue

    private static let classFlagsFieldOffset = ClassMetadataObjCInterop.Layout.offset(of: .flags)

    private static func build<MachO: ObjCImplementationClassReading & MachOSwiftSectionRepresentableWithCache>(in machO: MachO) -> Storage {
        var renamedClassesByDescriptorOffset: [Int: RenamedClass] = [:]
        var customRuntimeNamesBySwiftQualifiedName: [String: [String]] = [:]

        // Route 1: the class list, where a Swift class object is its metadata.
        for classObject in machO.objcImplementationClassObjects() ?? [] where classObject.isSwift {
            guard let classFlags: UInt32 = try? machO.readElement(offset: classObject.offset + classFlagsFieldOffset),
                  classFlags & ClassFlags.hasCustomObjCName.rawValue != 0,
                  classFlags & staticSpecializationClassFlags == 0
            else { continue }
            let descriptor: ClassDescriptor
            do {
                let descriptorPointer = try Pointer<ClassDescriptor?>.resolve(from: classObject.offset + ClassMetadataObjCInterop.descriptorOffset, in: machO)
                guard let resolvedDescriptor = try descriptorPointer.resolve(in: machO), resolvedDescriptor.layout.flags.kind == .class else {
                    #log(.error, "skipped a renamed class object at offset \(classObject.offset, privacy: .public): its metadata names no class descriptor")
                    continue
                }
                descriptor = resolvedDescriptor
            } catch {
                #log(.error, "skipped a renamed class object at offset \(classObject.offset, privacy: .public): descriptor unreadable: \(String(describing: error), privacy: .public)")
                continue
            }
            guard let readOnlyData = machO.instanceReadOnlyData(of: classObject), !readOnlyData.isMetaClass,
                  let runtimeName = machO.className(of: readOnlyData), !runtimeName.isEmpty
            else {
                #log(.error, "skipped a renamed class object at offset \(classObject.offset, privacy: .public): class name unreadable")
                continue
            }
            renamedClassesByDescriptorOffset[descriptor.offset] = RenamedClass(
                customObjCClassName: customObjCClassName(runtimeName: runtimeName, classFlags: classFlags, descriptor: descriptor),
                instanceStart: Int(readOnlyData.layout.instanceStart)
            )
            if let contextNode = try? SymbolicDemangler.demangleContext(for: .type(.class(descriptor)), in: machO),
               let qualifiedName = NodeTypeNaming.nominalQualifiedName(ofDemangledRoot: contextNode) {
                customRuntimeNamesBySwiftQualifiedName[qualifiedName, default: []].append(runtimeName)
            }
        }

        // Route 2: a resilient superclass keeps the class out of the class
        // list; its metadata pattern carries the same facts.
        let typeContextDescriptors = (try? machO.swift.typeContextDescriptors) ?? []
        for case .class(let descriptor) in typeContextDescriptors
            where descriptor.hasResilientSuperclass && !descriptor.layout.flags.isGeneric && descriptor.hasSingletonMetadataInitialization
            && renamedClassesByDescriptorOffset[descriptor.offset] == nil {
            guard let customObjCClassName = customObjCClassName(fromResilientPatternOf: descriptor, in: machO) else { continue }
            renamedClassesByDescriptorOffset[descriptor.offset] = RenamedClass(customObjCClassName: customObjCClassName, instanceStart: nil)
        }

        return Storage(renamedClassesByDescriptorOffset: renamedClassesByDescriptorOffset, customRuntimeNamesBySwiftQualifiedName: customRuntimeNamesBySwiftQualifiedName)
    }

    /// Reads the flag word and the `class_ro_t` name from the
    /// ``ResilientClassMetadataPattern`` a class with a resilient superclass
    /// keeps in the field its singleton metadata initialization otherwise
    /// spends on the incomplete metadata.
    private static func customObjCClassName<MachO: ObjCImplementationClassReading & MachOSwiftSectionRepresentableWithCache>(fromResilientPatternOf descriptor: ClassDescriptor, in machO: MachO) -> CustomObjCClassName? {
        do {
            // The wrapper walks the trailing objects to the initialization
            // record; transient, like every other materialization.
            let classWrapper = try Class(descriptor: descriptor, in: machO)
            guard let singletonMetadataInitialization = classWrapper.singletonMetadataInitialization,
                  let patternOffset = singletonMetadataInitialization.resolvedDirectOffset(from: \.incompleteMetadata)
            else { return nil }
            let pattern = try ResilientClassMetadataPattern.resolve(from: patternOffset, in: machO)
            let classFlags = pattern.layout.classFlags
            guard classFlags & ClassFlags.hasCustomObjCName.rawValue != 0,
                  let readOnlyDataOffset = pattern.resolvedDirectOffset(from: \.data)
            else { return nil }
            let readOnlyDataLayout: ObjCClassROData64.Layout = try machO.readElement(offset: readOnlyDataOffset)
            let readOnlyData = ObjCClassROData64(layout: readOnlyDataLayout, offset: readOnlyDataOffset)
            guard let runtimeName = machO.className(of: readOnlyData), !runtimeName.isEmpty else {
                #log(.error, "skipped the renamed class with descriptor at offset \(descriptor.offset, privacy: .public): class name unreadable from its metadata pattern")
                return nil
            }
            return customObjCClassName(runtimeName: runtimeName, classFlags: classFlags, descriptor: descriptor)
        } catch {
            #log(.error, "skipped the class with descriptor at offset \(descriptor.offset, privacy: .public): metadata pattern unreadable: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// The attribute follows the class's object model, the one fact the
    /// binary keeps beside the name: `UsesSwiftRefcounting` is clear exactly
    /// when the class uses the Objective-C object model (the compiler's
    /// `ClassDecl::getObjectModel()`), where `@objc(Name)` is legal. On the
    /// native object model it is not — except for an actor inheriting
    /// `NSObject` (`@objc actor`), which keeps Swift reference counting;
    /// `NSObject` is the only superclass an actor can have.
    private static func customObjCClassName(runtimeName: String, classFlags: UInt32, descriptor: ClassDescriptor) -> CustomObjCClassName {
        let usesSwiftReferenceCounting = classFlags & ClassFlags.usesSwiftRefcounting.rawValue != 0
        let isNSObjectActor = descriptor.isActor && descriptor.resolvedDirectOffset(from: \.superclassType) != nil
        let attribute: CustomObjCClassName.Attribute = !usesSwiftReferenceCounting || isNSObjectActor ? .objc : .objcRuntimeName
        return CustomObjCClassName(name: runtimeName, attribute: attribute)
    }
}
