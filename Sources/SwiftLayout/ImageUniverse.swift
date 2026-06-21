import MachOSwiftSection

/// The set of images the layout engine may resolve types against, plus the
/// resolution entry point the resolver uses to map a fully-qualified type name
/// to its defining image and descriptor.
///
/// The single-image phase builds this with `singleImage(_:)` and resolves only
/// within that one image. The dependency-closure phase will add a
/// `dependencyClosure(...)` factory that scans every image in the closure;
/// because the resolver only ever calls `resolveType(byQualifiedTypeName:)`,
/// that extension requires no resolver changes.
public final class ImageUniverse<MachO: MachOSwiftSectionRepresentableWithCache>: @unchecked Sendable {
    /// The root image (the binary whose types are being laid out).
    public let rootImage: ImageReference<MachO>

    init(rootImage: ImageReference<MachO>) {
        self.rootImage = rootImage
    }

    /// Builds a single-image universe: types resolve only within `machO`.
    public static func singleImage(_ machO: MachO) throws -> ImageUniverse<MachO> {
        ImageUniverse(rootImage: try ImageReference(machO: machO))
    }

    /// Resolves a fully-qualified type name to the image that defines it and
    /// its descriptor, or `nil` if no image in the universe defines it.
    func resolveType(
        byQualifiedTypeName qualifiedTypeName: String
    ) -> (image: ImageReference<MachO>, descriptor: TypeContextDescriptorWrapper)? {
        if let descriptor = rootImage.typeDescriptor(forQualifiedTypeName: qualifiedTypeName) {
            return (rootImage, descriptor)
        }
        return nil
    }

    /// Resolves a fully-qualified protocol name to its class constraint, or
    /// `nil` if no image in the universe defines that protocol. Used to decide
    /// whether an existential is class-bound.
    func resolveProtocolClassConstraint(
        byQualifiedTypeName qualifiedTypeName: String
    ) -> ProtocolClassConstraint? {
        rootImage.protocolClassConstraint(forQualifiedTypeName: qualifiedTypeName)
    }
}
