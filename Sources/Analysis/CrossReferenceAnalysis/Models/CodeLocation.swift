/// An address in the code of one image a ``CrossReferenceAnalyzer`` knows.
///
/// The address is the image's own, unslid — the one `dyld_info`, a
/// disassembler or a crash report's binary image list prints. Unslid
/// addresses of two images outside the dyld shared cache can coincide, so a
/// location carries its image.
public struct CodeLocation: Hashable, Comparable, Sendable {
    /// The image's position in ``CrossReferenceAnalyzer/images``.
    public let imageIndex: Int
    /// The unslid address.
    public let address: UInt64

    public init(imageIndex: Int, address: UInt64) {
        self.imageIndex = imageIndex
        self.address = address
    }

    public static func < (lhs: CodeLocation, rhs: CodeLocation) -> Bool {
        (lhs.imageIndex, lhs.address) < (rhs.imageIndex, rhs.address)
    }
}
