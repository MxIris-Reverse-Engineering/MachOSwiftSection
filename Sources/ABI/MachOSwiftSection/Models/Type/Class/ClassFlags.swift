import Foundation

/// Swift class flags.
/// These flags are valid only when isTypeMetadata().
/// When !isTypeMetadata() these flags will collide with other Swift ABIs.
public enum ClassFlags: UInt32 {
    /// Is this a Swift class from the Darwin pre-stable ABI?
    /// This bit is clear in stable ABI Swift classes.
    /// The Objective-C runtime also reads this bit.
    case isSwiftPreStableABI = 0x1
    /// Does this class use Swift refcounting?
    case usesSwiftRefcounting = 0x2
    /// Has this class a custom name, specified with the @objc attribute?
    case hasCustomObjCName = 0x4
    /// Whether this metadata is a specialization of a generic metadata pattern
    /// which was created during compilation.
    case isStaticSpecialization = 0x8
    /// Whether this metadata is a specialization of a generic metadata pattern
    /// which was created during compilation and made to be canonical by
    /// modifying the metadata accessor.
    case isCanonicalStaticSpecialization = 0x10
}
