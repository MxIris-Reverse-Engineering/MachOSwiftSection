import Foundation
import SwiftStdlibToolbox

/// Swift class flags.
/// These flags are valid only when isTypeMetadata().
/// When !isTypeMetadata() these flags will collide with other Swift ABIs.
///
/// Mirrors `swift::ClassFlags` (`swift/ABI/MetadataValues.h`). A set rather
/// than an enumeration, so that it holds the word a class's metadata carries,
/// several flags at once.
@FlagSet
public struct ClassFlags: Hashable, Sendable {
    public enum Flag: UInt32, CaseIterable, Sendable {
        /// Is this a Swift class from the Darwin pre-stable ABI?
        /// This bit is clear in stable ABI Swift classes.
        /// The Objective-C runtime also reads this bit.
        case isSwiftPreStableABI = 0
        /// Does this class use Swift refcounting?
        case usesSwiftRefcounting = 1
        /// Has this class a custom name, specified with the @objc attribute?
        case hasCustomObjCName = 2
        /// Whether this metadata is a specialization of a generic metadata pattern
        /// which was created during compilation.
        case isStaticSpecialization = 3
        /// Whether this metadata is a specialization of a generic metadata pattern
        /// which was created during compilation and made to be canonical by
        /// modifying the metadata accessor.
        case isCanonicalStaticSpecialization = 4
    }
}
