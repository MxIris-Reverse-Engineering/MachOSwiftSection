import Foundation
import MachOKit
import MachOSwiftSection
import Demangling
import SwiftThunkAnalysis

/// The platform version an availability-conditional opaque result type is
/// gated on (SE-0360's `if #available`, as the compiler wrote it into the
/// accessor thunk).
public struct PlatformAvailabilityCondition: Sendable, Hashable, Codable {
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
/// The production conformer is ``DisassemblingAccessorThunkResolver``, which
/// every rewrite uses unless a task scopes another through
/// ``AccessorThunkResolution/taskResolver``. The protocol exists so the
/// rewriter's contract can be pinned with a tabled stand-in — no disassembler,
/// no binary that happens to contain an availability-conditional opaque type.
public protocol AccessorThunkResolving: Sendable {
    /// The underlying types the thunk at `offset` yields, most-current branch
    /// first, or an empty array when the thunk's shape was not readable.
    /// `ownerLayout` names the generic parameters an argument the thunk reads
    /// stands for; pass ``AccessorThunkOwnerLayout/unknown`` when the owner
    /// is not known, and such a thunk then yields nothing rather than a
    /// half-named type.
    func underlyingTypes(forAccessorThunkAt offset: Int, in machO: MachOFile, ownerLayout: AccessorThunkOwnerLayout) -> [ConditionalUnderlyingType]
}

/// The resolver rendering uses: reads the thunk's instructions through
/// `SwiftThunkAnalysis`'s ``AccessorThunkReader``.
public struct DisassemblingAccessorThunkResolver: AccessorThunkResolving {
    public init() {}

    public func underlyingTypes(forAccessorThunkAt offset: Int, in machO: MachOFile, ownerLayout: AccessorThunkOwnerLayout) -> [ConditionalUnderlyingType] {
        guard let resolved = try? AccessorThunkReader.read(thunkAtOffset: offset, in: machO, ownerLayout: ownerLayout) else { return [] }
        return resolved.underlyingTypes.map { underlyingType in
            ConditionalUnderlyingType(
                availability: availabilityCondition(
                    for: underlyingType.condition,
                    check: resolved.availabilityCheck
                ),
                typeNode: underlyingType.typeNode
            )
        }
    }

    private func availabilityCondition(
        for condition: ThunkCandidate.Condition,
        check: PlatformAvailabilityCheck?
    ) -> PlatformAvailabilityCondition? {
        guard let check else { return nil }
        switch condition {
        case .unconditional:
            return nil
        case .availabilitySatisfied, .availabilityNotSatisfied:
            return PlatformAvailabilityCondition(
                platform: check.platform,
                major: check.major,
                minor: check.minor,
                patch: check.patch,
                isSatisfiedBranch: condition == .availabilitySatisfied
            )
        }
    }
}

/// Which ``AccessorThunkResolving`` a rewrite uses.
///
/// There is no process-wide registration: the disassembling resolver is the
/// default for every task. The only override is task-scoped, for tests that
/// need a rewrite to run against a stand-in (a tabled resolver, or one that
/// reads nothing, to pin the placeholder rendering) without touching what
/// parallel suites see.
public enum AccessorThunkResolution {
    /// A resolver for the current task tree only, taking precedence over the
    /// default ``DisassemblingAccessorThunkResolver``.
    @TaskLocal
    public static var taskResolver: (any AccessorThunkResolving)?

    /// The resolver a rewrite uses: the task's own when one is set, else the
    /// disassembling one.
    public static var effectiveResolver: any AccessorThunkResolving {
        taskResolver ?? DisassemblingAccessorThunkResolver()
    }
}
