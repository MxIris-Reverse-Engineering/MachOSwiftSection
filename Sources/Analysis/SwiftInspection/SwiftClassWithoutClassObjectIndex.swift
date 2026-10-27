import Foundation
import FoundationToolbox
import MachOKit
import MachOKitExtensions
import MachOReading
import MachOSwiftSection
@_spi(Internals) import Demangling
@_spi(Core) import MachOObjCSection
@_spi(Internals) import MachOCaches
@_spi(Internals) import MachOSymbols

/// A Swift class the image keeps no class object for (evolution proposal
/// `objc-classes-without-class-objects`): `__objc_classlist` does not list
/// it, yet its `class_ro_t` is emitted statically — the Objective-C runtime
/// only ever sees the class through metadata the Swift runtime builds or
/// initializes first. The fields are what `ObjCIndexing.ObjCSuppliedClass`
/// takes, plus what the library's own ObjC member table asks by.
package struct SwiftClassWithoutClassObject: Sendable, Hashable {
    /// Why the image keeps no class object — which of the compiler's class
    /// metadata strategies the class takes.
    package enum Kind: Sendable, Hashable {
        /// A generic class: each instantiation is built from the generic
        /// metadata pattern, whose extra data carries the `class_ro_t`
        /// template (its name a null pointer the runtime fills per
        /// instantiation).
        case generic
        /// A non-generic class whose superclass lives in another resilience
        /// domain (the Resilient strategy): the metadata is allocated at
        /// runtime from a `ResilientClassMetadataPattern`.
        case resilientAncestry
        /// A non-generic class whose metadata is emitted statically but must
        /// be initialized before the Objective-C runtime may see it (the
        /// Singleton strategy) — in practice a class with generic ancestry.
        case genericAncestry
    }

    /// How the class's superclass is named for the Objective-C side.
    package enum Superclass: Sendable, Hashable {
        /// An Objective-C class — or `_TtCs12_SwiftObject`, the superclass
        /// the runtime gives a Swift root class — by its runtime name, which
        /// is what the ancestor resolver looks a class up by.
        case objectiveC(runtimeName: String)
        /// A Swift class of the same image that has a class object, by the
        /// runtime name its `class_ro_t` carries.
        case classObject(runtimeName: String)
        /// Another class of the same image without a class object, by its
        /// ``SwiftClassWithoutClassObject/name``.
        case withoutClassObject(name: String)
        /// A Swift class this index cannot name for the Objective-C runtime —
        /// one another image defines — by its Swift spelling, for display.
        /// No ancestor walk can continue from it.
        case swiftClass(displayName: String)

        package var name: String {
            switch self {
            case .objectiveC(let runtimeName), .classObject(let runtimeName): runtimeName
            case .withoutClassObject(let name): name
            case .swiftClass(let displayName): displayName
            }
        }
    }

    package let kind: Kind
    /// The class's nominal type descriptor.
    package let descriptorOffset: Int
    /// The Swift qualified name, the key `ObjCMembers.table(forSwiftClassQualifiedName:in:)`
    /// is asked by (`Xcode_Service.MenuBarPanelWindow`).
    package let qualifiedName: String
    /// The name the class goes by on the Objective-C side: the `class_ro_t`
    /// name for a non-generic class (`_TtC13Xcode_Service23MenuBarLabelHostingView`);
    /// for a generic class, whose template names nothing, the qualified name
    /// with its generic parameters (`Xcode_Service.MenuBarPanelWindow<A>`).
    package let name: String
    package let superclass: Superclass
    /// Whether an Objective-C class is among the ancestors — what makes the
    /// compiler register a non-generic class's stub in `__objc_stublist`
    /// (`checkAncestry(AncestryFlags::ObjC)`). Read off the class flags: the
    /// Objective-C object model leaves `UsesSwiftRefcounting` clear, and an
    /// actor deriving from `NSObject`, the one exception, has a superclass.
    package let hasObjectiveCAncestry: Bool
    package let readOnlyDataOffset: Int
    package let metaclassReadOnlyDataOffset: Int?
    /// The isa word of the class's Objective-C class stub (`…CMs`), which
    /// the categories of its `@objc` extensions point at; `nil` for a
    /// generic class, which has none.
    package let classStubOffset: Int?
}

extension SwiftClassWithoutClassObject {
    func readOnlyData(in reader: some ObjCImplementationClassReading) -> ObjCClassROData64? {
        Self.readOnlyData(at: readOnlyDataOffset, in: reader)
    }

    func metaclassReadOnlyData(in reader: some ObjCImplementationClassReading) -> ObjCClassROData64? {
        metaclassReadOnlyDataOffset.flatMap { Self.readOnlyData(at: $0, in: reader) }
    }

    private static func readOnlyData(at offset: Int, in reader: some ObjCImplementationClassReading) -> ObjCClassROData64? {
        // `as`: bound to an optional, the `try?` read would take the
        // Optional's in-memory shape, one tag byte past the layout.
        guard let layout = try? reader.readElement(offset: offset) as ObjCClassROData64.Layout else { return nil }
        return ObjCClassROData64(layout: layout, offset: offset)
    }
}

/// Per-image index of the Swift classes without a class object (evolution
/// proposal `objc-classes-without-class-objects`), read from the type
/// context descriptors:
///
/// - A **generic** class's `class_ro_t` and metaclass `class_ro_t` sit in
///   the extra-data pattern of its generic metadata pattern. The runtime
///   copies that pattern into an instantiation's extra data at
///   `OffsetInWords` and points the metadata at word `ClassRODataOffset` of
///   the extra data (`initializeClassMetadataFromPattern`), so within the
///   pattern the template is word `ClassRODataOffset − OffsetInWords`.
/// - A class with a **resilient superclass** has its singleton metadata
///   initialization point at a `ResilientClassMetadataPattern` — its `data`
///   is the `class_ro_t`, its `metaclass` the static metaclass object — and
///   its descriptor at the class stub.
/// - A class initialized by the **singleton** pattern otherwise points at
///   the statically emitted incomplete metadata, a class object in shape;
///   only the stub list registers it, through a stub the descriptor does not
///   record, found here by its `…CMs` symbol. The Update and FixedOrUpdate
///   strategies initialize statically emitted metadata too, but theirs is in
///   the class list, and is left out here.
///
/// Every class is recorded whether or not it has Objective-C ancestry, as
/// the class list records every Swift class with a class object; what the
/// Objective-C side is handed is narrower (`ObjCSuppliedClass.swiftClassesWithoutClassObjects(in:)`
/// in SwiftIndexing). Absolute
/// pointers — the data and isa words of a class object — are read through
/// the ObjC reader, which decodes them in every accounting; the rest are
/// relative.
///
/// Built once per image, lazily, the first time the ObjC side asks about a
/// class the class list misses — an image that is merely an ObjC ancestor
/// never builds one — and evicted with the other ObjC-side per-image state.
/// This module sits below the event layer, so a class that could not be read
/// is only logged.
@Loggable(.private, subsystem: "com.machoswiftsection.swift-inspection", category: "SwiftClassWithoutClassObjectIndex")
package final class SwiftClassWithoutClassObjectIndex: @unchecked Sendable {
    package static let shared = SwiftClassWithoutClassObjectIndex()

    private let cache = SharedCache<Storage>(evictionGroup: .objcHierarchy, follows: [.symbolStore])

    private init() {}

    package final class Storage: @unchecked Sendable {
        /// In type-context-descriptor order.
        let classes: [SwiftClassWithoutClassObject]

        let classesByName: [String: SwiftClassWithoutClassObject]

        /// Swift qualified name → names. More than one entry means same-named
        /// private classes from different files, as in the ObjC-side indexes.
        let namesBySwiftQualifiedName: [String: [String]]

        init(classes: [SwiftClassWithoutClassObject]) {
            self.classes = classes
            var classesByName: [String: SwiftClassWithoutClassObject] = [:]
            var namesBySwiftQualifiedName: [String: [String]] = [:]
            for swiftClass in classes where classesByName[swiftClass.name] == nil {
                classesByName[swiftClass.name] = swiftClass
                namesBySwiftQualifiedName[swiftClass.qualifiedName, default: []].append(swiftClass.name)
            }
            self.classesByName = classesByName
            self.namesBySwiftQualifiedName = namesBySwiftQualifiedName
        }
    }

    /// The image's index, built on first use. The build re-types the reader
    /// once (`objcImplementationClassReader`): it needs the descriptors and
    /// the ObjC reads.
    package func storage(in machO: some MachORepresentableWithCache) -> Storage? {
        cache.storage(in: machO) { machO in
            machO.objcImplementationClassReader.map { Self.build(in: $0) }
        }
    }

    package func contains(in machO: some MachORepresentableWithCache) -> Bool {
        cache.contains(in: machO)
    }

    package func remove(for machO: some MachORepresentableWithCache) {
        cache.remove(for: machO)
    }

    // MARK: - Queries

    /// Every class of the image without a class object, in descriptor order.
    package func classes(in machO: some MachORepresentableWithCache) -> [SwiftClassWithoutClassObject] {
        storage(in: machO)?.classes ?? []
    }

    /// The class that goes by `name` on the Objective-C side.
    package func swiftClass(named name: String, in machO: some MachORepresentableWithCache) -> SwiftClassWithoutClassObject? {
        storage(in: machO)?.classesByName[name]
    }

    /// The Objective-C-side names of the classes whose Swift qualified name
    /// is `qualifiedName`; empty when there is none.
    package func names(forSwiftClassQualifiedName qualifiedName: String, in machO: some MachORepresentableWithCache) -> [String] {
        storage(in: machO)?.namesBySwiftQualifiedName[qualifiedName] ?? []
    }

    // MARK: - Build

    /// The superclass the runtime gives a Swift class that declares none.
    private static let swiftRootClassRuntimeName = "_TtCs12_SwiftObject"

    private static let classFlagsFieldOffset = ClassMetadataObjCInterop.Layout.offset(of: .flags)

    /// What one descriptor yields before its superclass is named: naming it
    /// needs every other class's name.
    private struct Reading {
        let descriptor: ClassDescriptor
        let kind: SwiftClassWithoutClassObject.Kind
        let qualifiedName: String
        let name: String
        let hasObjectiveCAncestry: Bool
        let readOnlyDataOffset: Int
        let metaclassReadOnlyDataOffset: Int?
        let classStubOffset: Int?
    }

    private static func build<MachO: ObjCImplementationClassReading & MachOSwiftSectionRepresentableWithCache>(in machO: MachO) -> Storage {
        // The class list's own index: which metadata is a class object, and
        // the runtime names of the Swift classes that have one.
        let classObjectStorage = ObjCClassMethodIndex.shared.storage(in: machO)
        let classObjectOffsets = Set(classObjectStorage?.classObjectsByRuntimeName.values.map(\.offset) ?? [])

        var readings: [Reading] = []
        let typeContextDescriptors = (try? machO.swift.typeContextDescriptors) ?? []
        for case .class(let descriptor) in typeContextDescriptors {
            if let reading = reading(of: descriptor, classObjectOffsets: classObjectOffsets, in: machO) {
                readings.append(reading)
            }
        }

        var namesByQualifiedName: [String: [String]] = [:]
        for reading in readings {
            namesByQualifiedName[reading.qualifiedName, default: []].append(reading.name)
        }
        let classes = readings.map { reading in
            SwiftClassWithoutClassObject(
                kind: reading.kind,
                descriptorOffset: reading.descriptor.offset,
                qualifiedName: reading.qualifiedName,
                name: reading.name,
                superclass: superclass(
                    of: reading.descriptor,
                    namesByQualifiedName: namesByQualifiedName,
                    classObjectRuntimeNamesByQualifiedName: classObjectStorage?.runtimeNamesBySwiftQualifiedName ?? [:],
                    in: machO
                ),
                hasObjectiveCAncestry: reading.hasObjectiveCAncestry,
                readOnlyDataOffset: reading.readOnlyDataOffset,
                metaclassReadOnlyDataOffset: reading.metaclassReadOnlyDataOffset,
                classStubOffset: reading.classStubOffset
            )
        }
        return Storage(classes: classes)
    }

    private static func reading<MachO: ObjCImplementationClassReading & MachOSwiftSectionRepresentableWithCache>(of descriptor: ClassDescriptor, classObjectOffsets: Set<Int>, in machO: MachO) -> Reading? {
        let context = machO.context
        do {
            let kind: SwiftClassWithoutClassObject.Kind
            let readOnlyData: ObjCClassROData64
            let metaclassReadOnlyData: ObjCClassROData64?
            let classFlags: UInt32
            var classStubOffset: Int?
            if descriptor.layout.flags.isGeneric {
                guard let genericContext = try descriptor.typeGenericContext(in: context),
                      let patternOffset = genericContext.header.resolvedDirectOffset(from: \.defaultInstantiationPattern)
                else { return nil }
                let pattern = try GenericClassMetadataPattern.resolve(at: patternOffset, in: context)
                // No extra-data pattern: a build without Objective-C interop.
                guard let extraDataPattern = try pattern.extraDataPattern(in: context),
                      let extraDataOffset = extraDataPattern.resolvedDirectOffset(from: \.pattern)
                else { return nil }
                func offset(ofExtraDataWordAt wordOffset: UInt16) -> Int? {
                    let wordIndex = Int(wordOffset) - Int(extraDataPattern.layout.offsetInWords)
                    guard wordIndex >= 0, wordIndex < Int(extraDataPattern.layout.sizeInWords) else { return nil }
                    return extraDataOffset + wordIndex * MemoryLayout<UInt64>.size
                }
                guard let readOnlyDataOffset = offset(ofExtraDataWordAt: pattern.layout.classReadOnlyDataOffsetInWords) else {
                    #log(.error, "skipped the generic class with descriptor at offset \(descriptor.offset, privacy: .public): its class_ro_t lies outside the extra-data pattern")
                    return nil
                }
                kind = .generic
                classFlags = pattern.layout.classFlags
                readOnlyData = try readOnlyDataTemplate(at: readOnlyDataOffset, in: machO)
                metaclassReadOnlyData = try offset(ofExtraDataWordAt: pattern.layout.metaclassReadOnlyDataOffsetInWords).map { try readOnlyDataTemplate(at: $0, in: machO) }
            } else if descriptor.hasSingletonMetadataInitialization {
                // The wrapper walks the trailing objects to the initialization
                // record; transient, like every other materialization.
                let classWrapper = try Class(descriptor: descriptor, in: context)
                guard let initialization = classWrapper.singletonMetadataInitialization,
                      let metadataOffset = initialization.resolvedDirectOffset(from: \.incompleteMetadata)
                else { return nil }
                if descriptor.hasResilientSuperclass {
                    // The field names the resilient pattern instead.
                    let pattern = try ResilientClassMetadataPattern.resolve(at: metadataOffset, in: context)
                    guard let readOnlyDataOffset = pattern.resolvedDirectOffset(from: \.data) else { return nil }
                    kind = .resilientAncestry
                    classFlags = pattern.layout.classFlags
                    readOnlyData = try readOnlyDataTemplate(at: readOnlyDataOffset, in: machO)
                    metaclassReadOnlyData = try pattern.resolvedDirectOffset(from: \.metaclass).flatMap { try instanceReadOnlyData(ofClassObjectAt: $0, in: machO) }
                    classStubOffset = classWrapper.objcResilientClassStubInfo?.resolvedDirectOffset(from: \.stub)
                } else {
                    guard !classObjectOffsets.contains(metadataOffset) else { return nil }
                    let classObject = try classObject(at: metadataOffset, in: machO)
                    guard let instanceReadOnlyData = machO.instanceReadOnlyData(of: classObject) else {
                        #log(.error, "skipped the class with descriptor at offset \(descriptor.offset, privacy: .public): its incomplete metadata carries no readable class_ro_t")
                        return nil
                    }
                    kind = .genericAncestry
                    // `as UInt32`: bound to an optional, the read would take
                    // the Optional's in-memory shape, one tag byte past it.
                    classFlags = try machO.readElement(offset: metadataOffset + classFlagsFieldOffset) as UInt32
                    readOnlyData = instanceReadOnlyData
                    metaclassReadOnlyData = machO.metaClass(of: classObject).flatMap { machO.instanceReadOnlyData(of: $0) }
                    classStubOffset = singletonClassStubOffset(of: descriptor, in: machO)
                }
            } else {
                // Fixed strategy: the class object is in the class list.
                return nil
            }
            guard !readOnlyData.isMetaClass else {
                #log(.error, "skipped the class with descriptor at offset \(descriptor.offset, privacy: .public): its class_ro_t is marked as a metaclass's")
                return nil
            }
            let contextNode = try SymbolicDemangler.demangleContext(for: .type(.class(descriptor)), in: context)
            guard let qualifiedName = NodeTypeNaming.nominalQualifiedName(ofDemangledRoot: contextNode) else { return nil }
            let name: String
            if kind == .generic {
                name = qualifiedName + genericParameterClause(of: descriptor, in: machO)
            } else {
                guard let runtimeName = machO.className(of: readOnlyData), !runtimeName.isEmpty else {
                    #log(.error, "skipped the class with descriptor at offset \(descriptor.offset, privacy: .public): class name unreadable")
                    return nil
                }
                name = runtimeName
            }
            let usesSwiftReferenceCounting = classFlags & ClassFlags.usesSwiftRefcounting.rawValue != 0
            let isNSObjectActor = descriptor.isActor && descriptor.resolvedDirectOffset(from: \.superclassType) != nil
            return Reading(
                descriptor: descriptor,
                kind: kind,
                qualifiedName: qualifiedName,
                name: name,
                hasObjectiveCAncestry: !usesSwiftReferenceCounting || isNSObjectActor,
                readOnlyDataOffset: readOnlyData.offset,
                // A pointer that misread lands on a class's own data, never a
                // metaclass's.
                metaclassReadOnlyDataOffset: metaclassReadOnlyData.flatMap { $0.isMetaClass ? $0.offset : nil },
                classStubOffset: classStubOffset
            )
        } catch {
            #log(.error, "skipped the class with descriptor at offset \(descriptor.offset, privacy: .public): metadata unreadable: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private static func readOnlyDataTemplate(at offset: Int, in machO: some ObjCImplementationClassReading) throws -> ObjCClassROData64 {
        let layout: ObjCClassROData64.Layout = try machO.readElement(offset: offset)
        return ObjCClassROData64(layout: layout, offset: offset)
    }

    private static func classObject(at offset: Int, in machO: some ObjCImplementationClassReading) throws -> ObjCClass64 {
        let layout: ObjCClass64.Layout = try machO.readElement(offset: offset)
        return ObjCClass64(layout: layout, offset: offset)
    }

    private static func instanceReadOnlyData(ofClassObjectAt offset: Int, in machO: some ObjCImplementationClassReading) throws -> ObjCClassROData64? {
        machO.instanceReadOnlyData(of: try classObject(at: offset, in: machO))
    }

    /// `<A, B>`: the parameters of every depth, named by depth and index as
    /// everywhere else the binary keeps no names (`Outer<A>.Inner<B>` gives
    /// `<A, A1>`).
    private static func genericParameterClause(of descriptor: ClassDescriptor, in machO: some MachOSwiftSectionRepresentableWithCache) -> String {
        guard let depthLayout = try? GenericParameterDepthLayout.make(for: .type(.class(descriptor)), in: machO.context), depthLayout.parameterCount > 0 else { return "" }
        var parameterNames: [String] = []
        for (depth, parameterCount) in depthLayout.parameterCountsByDepth.enumerated() {
            for index in 0 ..< parameterCount {
                parameterNames.append(genericParameterName(depth: UInt64(depth), index: UInt64(index)))
            }
        }
        return "<" + parameterNames.joined(separator: ", ") + ">"
    }

    /// The stub of a class initialized by the singleton pattern, which the
    /// descriptor does not record: the symbol named like the descriptor's
    /// (`…CMn`) with the stub's suffix (`…CMs`). A stripped image keeps
    /// neither, and the stub goes unnamed.
    private static func singletonClassStubOffset(of descriptor: ClassDescriptor, in machO: some MachORepresentableWithCache) -> Int? {
        guard let descriptorSymbolName = machO.symbols(offset: descriptor.offset)?.first(where: { $0.name.hasSuffix("CMn") })?.name else { return nil }
        return SymbolIndexStore.shared.offset(ofSymbolNamed: String(descriptorSymbolName.dropLast()) + "s", in: machO)
    }

    private static func superclass(
        of descriptor: ClassDescriptor,
        namesByQualifiedName: [String: [String]],
        classObjectRuntimeNamesByQualifiedName: [String: [String]],
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) -> SwiftClassWithoutClassObject.Superclass {
        let context = machO.context
        let superclassNode: Node
        do {
            guard let mangledName = try descriptor.superclassTypeMangledName(in: context) else {
                return .objectiveC(runtimeName: swiftRootClassRuntimeName)
            }
            superclassNode = try SymbolicDemangler.demangleTypeUncached(for: mangledName, in: context)
        } catch {
            #log(.error, "the superclass of the class with descriptor at offset \(descriptor.offset, privacy: .public) is unreadable: \(String(describing: error), privacy: .public)")
            return .swiftClass(displayName: "")
        }
        let displayName = superclassNode.print(using: .interfaceType)
        var nominalNode = superclassNode.kind == .type ? superclassNode.firstChild : superclassNode
        let isBoundGeneric = nominalNode?.kind == .boundGenericClass
        if isBoundGeneric {
            nominalNode = nominalNode?.firstChild.flatMap { $0.kind == .type ? $0.firstChild : $0 }
        }
        guard let classNode = nominalNode, classNode.kind == .class else { return .swiftClass(displayName: displayName) }
        if let module = classNode.firstChild, module.kind == .module, module.text == objcModule, let runtimeName = classNode.children.at(1)?.text {
            return .objectiveC(runtimeName: runtimeName)
        }
        guard let qualifiedName = NodeTypeNaming.nominalQualifiedName(of: classNode) else { return .swiftClass(displayName: displayName) }
        if let names = namesByQualifiedName[qualifiedName], names.count == 1 {
            return .withoutClassObject(name: names[0])
        }
        if !isBoundGeneric {
            let runtimeNames = (classObjectRuntimeNamesByQualifiedName[qualifiedName] ?? []) + SwiftClassObjectIndex.shared.customRuntimeNames(forSwiftClassQualifiedName: qualifiedName, in: machO)
            if runtimeNames.count == 1 {
                return .classObject(runtimeName: runtimeNames[0])
            }
        }
        return .swiftClass(displayName: displayName)
    }
}
