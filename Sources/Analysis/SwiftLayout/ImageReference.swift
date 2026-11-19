import MachOKit
@_spi(Internals) import MachOCaches
import MachOSwiftSection
@_spi(Internals) import SwiftInspection
import Demangling

/// A single Mach-O image plus the per-image indexes the layout engine needs:
/// a fully-qualified-name → type-descriptor map (so a field's demangled type
/// name can be resolved back to its descriptor) and the builtin layout index.
///
/// The resolver carries an `ImageReference` through recursion as "the image
/// the current type is defined in". In the single-image phase there is exactly
/// one; the dependency-closure phase adds more without changing the resolver.
///
/// Each index is built the first time it is read (evolution proposal
/// `machofile-performance`). A dependency is folded into a universe for one
/// kind of lookup at a time, and most are asked about one kind only: building
/// all seven at once read every dependency's Objective-C protocol list — 2.4
/// of the 12 seconds the indexes of SwiftUI's dependencies cost — for the
/// rare existential over a Swift-declared `@objc` protocol. An index that
/// cannot be read is empty rather than discarding the image.
public final class ImageReference<MachO: MachOSwiftSectionRepresentableWithCache>: @unchecked Sendable {
    public let machO: MachO

    private let builtinLayoutIndexSlot = LazilyBuiltIndex<BuiltinTypeLayoutIndex>()
    private let typeDescriptorsSlot = LazilyBuiltIndex<[String: TypeContextDescriptorWrapper]>()
    private let protocolClassConstraintsSlot = LazilyBuiltIndex<[String: ProtocolClassConstraint]>()
    private let objCClassInstanceSizesSlot = LazilyBuiltIndex<[String: (instanceSize: Int, alignmentMask: Int)]>()
    private let associatedTypeWitnessRecordsSlot = LazilyBuiltIndex<[String: AssociatedTypeRecord]>()
    private let objCProtocolQualifiedNamesSlot = LazilyBuiltIndex<Set<String>>()
    private let swiftClassInstanceStartsSlot = LazilyBuiltIndex<[String: Int]>()

    /// Never throws: the indexes are built when first read. Kept throwing so
    /// existing `try ImageReference(machO:)` call sites stay valid.
    public convenience init(machO: MachO) throws {
        self.init(indexingLazily: machO)
    }

    init(indexingLazily machO: MachO) {
        self.machO = machO
    }

    /// The image's reference shared by every universe that folds it in, so
    /// an index one root's layouts built serves every other root that
    /// depends on the image — RuntimeViewer lays out one root after another
    /// against the same system frameworks, and a root has a universe for the
    /// printer and another for associated-type projection.
    ///
    /// A reader of another type that shares the image's key — a wrapper and
    /// the reader it wraps share an identifier — gets a reference of its own.
    static func shared(for machO: MachO) -> ImageReference<MachO> {
        let sharedReference = ImageReferenceStore.cache.storage(in: machO) { machO -> AnyObject? in
            ImageReference(indexingLazily: machO)
        }
        return sharedReference as? ImageReference<MachO> ?? ImageReference(indexingLazily: machO)
    }

    /// The image's `__swift5_builtin` layouts.
    var builtinLayoutIndex: BuiltinTypeLayoutIndex {
        builtinLayoutIndexSlot.index {
            (try? BuiltinTypeLayoutIndex(machO: machO)) ?? .empty
        }
    }

    /// Exposed (package-internal) so `ImageUniverse` can merge each image's
    /// per-image index into the closure-wide global index. Keyed by
    /// fully-qualified type name.
    ///
    /// `demangleContext` reconstructs the fully-qualified name from the
    /// descriptor's parent chain (the descriptor's own `mangledName` is not a
    /// demangleable type reference). A dependency image with no Swift type
    /// section (a pure-ObjC/C dylib) contributes no types rather than failing
    /// the whole closure.
    var typeDescriptorsByQualifiedName: [String: TypeContextDescriptorWrapper] {
        typeDescriptorsSlot.index {
            var typeIndex: [String: TypeContextDescriptorWrapper] = [:]
            for contextDescriptor in (try? Self.contextDescriptorsOrEmpty(in: machO)) ?? [] {
                guard
                    let typeDescriptor = contextDescriptor.typeContextDescriptorWrapper,
                    let contextNode = try? SymbolicDemangler.demangleContext(for: contextDescriptor, in: machO.context),
                    let qualifiedTypeName = NodeTypeNaming.nominalQualifiedName(of: contextNode)
                else { continue }
                typeIndex[qualifiedTypeName] = typeDescriptor
            }
            return typeIndex
        }
    }

    /// Exposed (package-internal) so `ImageUniverse` can merge each image's
    /// protocol class-constraint index into the closure-wide global index.
    ///
    /// Every Swift protocol's class constraint, from `__swift5_protos` (a
    /// separate section from the type context descriptors), so an
    /// existential's representation — opaque vs class-bound — can be derived
    /// from its protocol composition.
    var protocolClassConstraintsByQualifiedName: [String: ProtocolClassConstraint] {
        protocolClassConstraintsSlot.index {
            var protocolIndex: [String: ProtocolClassConstraint] = [:]
            for protocolDescriptor in (try? Self.protocolDescriptorsOrEmpty(in: machO)) ?? [] {
                guard
                    let classConstraint = protocolDescriptor.flags.kindSpecificFlags?.protocolFlags?.classConstraint,
                    let contextNode = try? SymbolicDemangler.demangleContext(for: .protocol(protocolDescriptor), in: machO.context),
                    let qualifiedTypeName = NodeTypeNaming.declaredQualifiedName(of: contextNode)
                else { continue }
                protocolIndex[qualifiedTypeName] = classConstraint
            }
            return protocolIndex
        }
    }

    /// Exposed (package-internal) so `ImageUniverse` can merge each image's
    /// Objective-C class start layouts into the closure-wide index. Keyed by
    /// bare ObjC class name (ObjC class names carry no module qualifier).
    ///
    /// Every Objective-C class's instance size, from `__objc_classlist`, so a
    /// Swift class with an ObjC ancestor can start its own fields at the
    /// ancestor's instance size — the ObjC class has no Swift descriptor, so it
    /// is invisible to the type index. Read through the concrete reader
    /// because the ObjC accessors are not protocol-generic.
    var objCClassInstanceSizesByBareName: [String: (instanceSize: Int, alignmentMask: Int)] {
        objCClassInstanceSizesSlot.index {
            Self.objCClassInstanceSizes(in: machO)
        }
    }

    /// Exposed (package-internal) so `ImageUniverse` can merge each image's
    /// associated-type witnesses into the closure-wide index. Keyed by
    /// `"conformingQualifiedName|protocolQualifiedName|associatedTypeName"`; the
    /// value is the `__swift5_assocty` record whose `substitutedTypeName` is the
    /// witness type (demangled on demand, in this image). Lets the resolver turn
    /// a `dependentMemberType` — `Array.Index` after substituting the base —
    /// into the concrete witness (`Int`).
    ///
    /// The conforming type and protocol names are demangled to the same
    /// qualified-name form the resolver computes on the lookup side; a record
    /// whose names cannot be demangled is skipped. An absent section
    /// contributes nothing.
    var associatedTypeWitnessRecordsByKey: [String: AssociatedTypeRecord] {
        associatedTypeWitnessRecordsSlot.index {
            var witnessIndex: [String: AssociatedTypeRecord] = [:]
            for descriptor in (try? Self.associatedTypeDescriptorsOrEmpty(in: machO)) ?? [] {
                guard
                    let conformingNode = try? SymbolicDemangler.demangleType(for: descriptor.conformingTypeName(in: machO.context), in: machO.context),
                    let conformingName = NodeTypeNaming.nominalQualifiedName(of: conformingNode),
                    let protocolNode = try? SymbolicDemangler.demangleType(for: descriptor.protocolTypeName(in: machO.context), in: machO.context),
                    let protocolName = NodeTypeNaming.protocolQualifiedName(of: protocolNode),
                    let records = try? descriptor.associatedTypeRecords(in: machO.context)
                else { continue }
                for record in records {
                    guard let associatedTypeName = try? record.name(in: machO.context) else { continue }
                    witnessIndex[Self.associatedTypeWitnessKey(conformingName: conformingName, protocolName: protocolName, associatedTypeName: associatedTypeName)] = record
                }
            }
            return witnessIndex
        }
    }

    /// Exposed (package-internal) so `ImageUniverse` can merge each image's
    /// Objective-C protocol declarations (`__objc_protolist`) into the
    /// closure-wide index. Keyed by Swift qualified name, parsed from the
    /// legacy `_TtP…_` mangling; a hit identifies a Swift-declared `@objc`
    /// protocol, which emits no Swift protocol descriptor but is always
    /// class-bound and carries no Swift witness table — so an existential over
    /// one can still be laid out as a class-bound component.
    var objCProtocolQualifiedNames: Set<String> {
        objCProtocolQualifiedNamesSlot.index {
            Self.objCProtocolQualifiedNames(in: machO)
        }
    }

    /// Swift qualified name → the class's **own** `class_ro_t.instanceStart`,
    /// for every statically-emitted Swift class in this image's
    /// `__objc_classlist`. This is the authoritative field-block start the
    /// ObjC runtime slides (`moveIvars`) — a cache-resident image carries the
    /// pre-slid final value. Classlist membership itself discriminates the
    /// initialization mode: generic and singleton-initialized classes are
    /// absent and keep the Swift-runtime rule (exact superclass size).
    /// Queried only for classes defined in this image, so it never merges
    /// into the closure-wide index.
    var swiftClassInstanceStartsByQualifiedName: [String: Int] {
        swiftClassInstanceStartsSlot.index {
            Self.swiftClassInstanceStarts(in: machO)
        }
    }

    /// Looks up a type descriptor by its fully-qualified name (as produced by
    /// `NodeTypeNaming.nominalQualifiedName`).
    func typeDescriptor(forQualifiedTypeName qualifiedTypeName: String) -> TypeContextDescriptorWrapper? {
        typeDescriptorsByQualifiedName[qualifiedTypeName]
    }

    /// The associated-type witness key format shared by the index and lookup
    /// sides: `"conformingQualifiedName|protocolQualifiedName|associatedTypeName"`.
    static func associatedTypeWitnessKey(conformingName: String, protocolName: String, associatedTypeName: String) -> String {
        "\(conformingName)|\(protocolName)|\(associatedTypeName)"
    }

    /// Looks up a Swift protocol's class constraint by its fully-qualified name,
    /// or `nil` if no protocol with that name is defined in this image.
    func protocolClassConstraint(forQualifiedTypeName qualifiedTypeName: String) -> ProtocolClassConstraint? {
        protocolClassConstraintsByQualifiedName[qualifiedTypeName]
    }

    /// Builds the bare-name → ObjC-class start-layout index, dispatching to the
    /// `MachOImage` / `MachOFile` ObjC reader the reader reads through. Any
    /// other reader (or an image with no ObjC classes) contributes nothing.
    private static func objCClassInstanceSizes(in machO: MachO) -> [String: (instanceSize: Int, alignmentMask: Int)] {
        if let inProcessImage = machO.asMachOImage {
            return ObjCClassIndex.instanceSizesByBareName(in: inProcessImage)
        }
        if let fileImage = machO.asMachOFile {
            return ObjCClassIndex.instanceSizesByBareName(in: fileImage)
        }
        return [:]
    }

    /// Builds the Swift-qualified-name → own-`instanceStart` index for the
    /// image's statically-emitted Swift classes, dispatching to the
    /// `MachOImage` / `MachOFile` ObjC reader the reader reads through.
    private static func swiftClassInstanceStarts(in machO: MachO) -> [String: Int] {
        if let inProcessImage = machO.asMachOImage {
            return ObjCClassIndex.swiftClassInstanceStartsByQualifiedName(in: inProcessImage)
        }
        if let fileImage = machO.asMachOFile {
            return ObjCClassIndex.swiftClassInstanceStartsByQualifiedName(in: fileImage)
        }
        return [:]
    }

    /// Builds the Swift-qualified-name index of the image's `@objc` protocol
    /// declarations, dispatching to the `MachOImage` / `MachOFile` ObjC reader
    /// the reader reads through. Any other reader (or an image with no ObjC
    /// protocols) contributes nothing.
    private static func objCProtocolQualifiedNames(in machO: MachO) -> Set<String> {
        if let inProcessImage = machO.asMachOImage {
            return ObjCProtocolIndex.qualifiedNames(in: inProcessImage)
        }
        if let fileImage = machO.asMachOFile {
            return ObjCProtocolIndex.qualifiedNames(in: fileImage)
        }
        return []
    }

    /// Reads the image's type context descriptors, treating an absent
    /// `__swift5_types` section as "no Swift types" rather than an error.
    /// Any other read error propagates — matches `BuiltinTypeLayoutIndex`.
    private static func contextDescriptorsOrEmpty(in machO: MachO) throws -> [ContextDescriptorWrapper] {
        do {
            return try machO.swift.contextDescriptors
        } catch let MachOSwiftSectionError.sectionNotFound(section, _) where section == .__swift5_types {
            return []
        }
    }

    /// Reads the image's protocol descriptors, treating an absent
    /// `__swift5_protos` section as "no Swift protocols" rather than an error.
    /// Any other read error propagates — matches `BuiltinTypeLayoutIndex`.
    private static func protocolDescriptorsOrEmpty(in machO: MachO) throws -> [ProtocolDescriptor] {
        do {
            return try machO.swift.protocolDescriptors
        } catch let MachOSwiftSectionError.sectionNotFound(section, _) where section == .__swift5_protos {
            return []
        }
    }

    /// Reads the image's associated-type descriptors, treating an absent
    /// `__swift5_assocty` section as "no associated types" rather than an error.
    private static func associatedTypeDescriptorsOrEmpty(in machO: MachO) throws -> [AssociatedTypeDescriptor] {
        do {
            return try machO.swift.associatedTypeDescriptors
        } catch let MachOSwiftSectionError.sectionNotFound(section, _) where section == .__swift5_assocty {
            return []
        }
    }
}

/// The per-image cache behind `ImageReference.shared(for:)`. It holds the
/// references untyped because a generic type cannot hold a static stored
/// property.
private enum ImageReferenceStore {
    static let cache = SharedCache<AnyObject>(evictionGroup: .layoutImageIndexes)
}

extension ImageReference {
    /// The indexes built so far, by name, for tests watching which lookups
    /// build what.
    var builtIndexNamesForTesting: Set<String> {
        var builtIndexNames: Set<String> = []
        if builtinLayoutIndexSlot.isBuilt { builtIndexNames.insert("builtinLayouts") }
        if typeDescriptorsSlot.isBuilt { builtIndexNames.insert("typeDescriptors") }
        if protocolClassConstraintsSlot.isBuilt { builtIndexNames.insert("protocolClassConstraints") }
        if objCClassInstanceSizesSlot.isBuilt { builtIndexNames.insert("objCClassInstanceSizes") }
        if associatedTypeWitnessRecordsSlot.isBuilt { builtIndexNames.insert("associatedTypeWitnessRecords") }
        if objCProtocolQualifiedNamesSlot.isBuilt { builtIndexNames.insert("objCProtocolQualifiedNames") }
        if swiftClassInstanceStartsSlot.isBuilt { builtIndexNames.insert("swiftClassInstanceStarts") }
        return builtIndexNames
    }
}
