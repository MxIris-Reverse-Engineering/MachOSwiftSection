import Foundation
import MachOKit
import Demangling
import FoundationToolbox

/// The platform version an availability-conditional opaque result type is
/// gated on (SE-0360's `if #available`, as the compiler wrote it into the
/// accessor thunk).
public struct PlatformAvailabilityCondition: Sendable, Hashable {
    /// `__isPlatformVersionAtLeast`'s first argument. Not translated to a
    /// named platform here: the numbering is compiler-rt's, and mapping it
    /// wrong would attribute a type to the wrong OS in rendered output.
    public let platform: UInt32
    public let major: UInt32
    public let minor: UInt32
    public let patch: UInt32
    /// `true` for the branch taken when the platform is at least that version.
    public let isSatisfiedBranch: Bool

    public init(platform: UInt32, major: UInt32, minor: UInt32, patch: UInt32, isSatisfiedBranch: Bool) {
        self.platform = platform
        self.major = major
        self.minor = minor
        self.patch = patch
        self.isSatisfiedBranch = isSatisfiedBranch
    }
}

/// One underlying type an accessor thunk can yield.
public struct ConditionalUnderlyingType: Sendable {
    /// `nil` when the thunk has no version check and this is its only answer.
    public let availability: PlatformAvailabilityCondition?
    public let typeNode: Node

    public init(availability: PlatformAvailabilityCondition?, typeNode: Node) {
        self.availability = availability
        self.typeNode = typeNode
    }
}

/// Resolves a kind-9 accessor-function symbolic reference to the type(s) it
/// stands for.
///
/// The seam exists so this module does **not** depend on the disassembler.
/// `SwiftThunkAnalysis` implements it and registers the implementation; with
/// the `ThunkAnalysis` trait off nothing registers and rendering falls back to
/// the placeholder, exactly as before.
public protocol AccessorThunkResolving: Sendable {
    /// The underlying types the thunk at `offset` yields, most-current branch
    /// first, or an empty array when the thunk's shape was not readable.
    func underlyingTypes(forAccessorThunkAt offset: Int, in machO: MachOFile) -> [ConditionalUnderlyingType]
}

/// Process-wide registration point for an ``AccessorThunkResolving``.
///
/// A global rather than a parameter threaded through the render configuration
/// because the call site is deep inside a `Node.Rewriter` that the dump path,
/// the interface path and the diff path all reach independently; adding a
/// parameter to all three for a feature that is off by default would be the
/// tail wagging the dog. Same shape as
/// `MachOSymbols.Symbol.resolvesSymbolUsingIndexStore`.
public enum AccessorThunkResolution {
    @Mutex
    public static var resolver: (any AccessorThunkResolving)?
}
