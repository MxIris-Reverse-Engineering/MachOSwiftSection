import MachOKit
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
public final class ImageReference<MachO: MachOSwiftSectionRepresentableWithCache>: @unchecked Sendable {
    public let machO: MachO
    let builtinLayoutIndex: BuiltinTypeLayoutIndex
    /// Exposed (package-internal) so `ImageUniverse` can merge each image's
    /// per-image index into the closure-wide global index. Keyed by
    /// fully-qualified type name.
    let typeDescriptorsByQualifiedName: [String: TypeContextDescriptorWrapper]
    /// Exposed (package-internal) so `ImageUniverse` can merge each image's
    /// protocol class-constraint index into the closure-wide global index.
    let protocolClassConstraintsByQualifiedName: [String: ProtocolClassConstraint]
    /// Exposed (package-internal) so `ImageUniverse` can merge each image's
    /// Objective-C class start layouts into the closure-wide index. Keyed by
    /// bare ObjC class name (ObjC class names carry no module qualifier).
    let objCClassInstanceSizesByBareName: [String: (instanceSize: Int, alignmentMask: Int)]

    public init(machO: MachO) throws {
        self.machO = machO
        self.builtinLayoutIndex = try BuiltinTypeLayoutIndex(machO: machO)

        // `demangleContext` reconstructs the fully-qualified name from the
        // descriptor's parent chain (the descriptor's own `mangledName` is not a
        // demangleable type reference). A dependency image with no Swift type
        // section (a pure-ObjC/C dylib) contributes no types rather than failing
        // the whole closure.
        var typeIndex: [String: TypeContextDescriptorWrapper] = [:]
        for contextDescriptor in try Self.contextDescriptorsOrEmpty(in: machO) {
            guard
                let typeDescriptor = contextDescriptor.typeContextDescriptorWrapper,
                let contextNode = try? MetadataReader.demangleContext(for: contextDescriptor, in: machO),
                let qualifiedTypeName = NodeTypeNaming.nominalQualifiedName(of: contextNode)
            else { continue }
            typeIndex[qualifiedTypeName] = typeDescriptor
        }
        self.typeDescriptorsByQualifiedName = typeIndex

        // Index every Swift protocol's class constraint (from `__swift5_protos`,
        // a separate section from the type context descriptors) so an
        // existential's representation — opaque vs class-bound — can be derived
        // from its protocol composition.
        var protocolIndex: [String: ProtocolClassConstraint] = [:]
        for protocolDescriptor in try Self.protocolDescriptorsOrEmpty(in: machO) {
            guard
                let classConstraint = protocolDescriptor.flags.kindSpecificFlags?.protocolFlags?.classConstraint,
                let contextNode = try? MetadataReader.demangleContext(for: .protocol(protocolDescriptor), in: machO),
                let qualifiedTypeName = NodeTypeNaming.declaredQualifiedName(of: contextNode)
            else { continue }
            protocolIndex[qualifiedTypeName] = classConstraint
        }
        self.protocolClassConstraintsByQualifiedName = protocolIndex

        // Index every Objective-C class's instance size (from `__objc_classlist`)
        // so a Swift class with an ObjC ancestor can start its own fields at the
        // ancestor's instance size — the ObjC class has no Swift descriptor, so
        // it is invisible to the type index above. Read through the concrete
        // reader because the ObjC accessors are not protocol-generic.
        self.objCClassInstanceSizesByBareName = Self.objCClassInstanceSizes(in: machO)
    }

    /// Looks up a type descriptor by its fully-qualified name (as produced by
    /// `NodeTypeNaming.nominalQualifiedName`).
    func typeDescriptor(forQualifiedTypeName qualifiedTypeName: String) -> TypeContextDescriptorWrapper? {
        typeDescriptorsByQualifiedName[qualifiedTypeName]
    }

    /// Looks up a Swift protocol's class constraint by its fully-qualified name,
    /// or `nil` if no protocol with that name is defined in this image.
    func protocolClassConstraint(forQualifiedTypeName qualifiedTypeName: String) -> ProtocolClassConstraint? {
        protocolClassConstraintsByQualifiedName[qualifiedTypeName]
    }

    /// Builds the bare-name → ObjC-class start-layout index, dispatching to the
    /// concrete `MachOImage` / `MachOFile` ObjC reader. A reader the engine does
    /// not recognize (or an image with no ObjC classes) contributes nothing.
    private static func objCClassInstanceSizes(in machO: MachO) -> [String: (instanceSize: Int, alignmentMask: Int)] {
        if let inProcessImage = machO as? MachOImage {
            return ObjCClassIndex.instanceSizesByBareName(in: inProcessImage)
        }
        if let fileImage = machO as? MachOFile {
            return ObjCClassIndex.instanceSizesByBareName(in: fileImage)
        }
        return [:]
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
}
