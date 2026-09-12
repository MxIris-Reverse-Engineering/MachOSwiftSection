#if THUNK_ANALYSIS

import Foundation

/// The `__isPlatformVersionAtLeast(platform, major, minor, patch)` call a
/// thunk makes before choosing between its candidates.
///
/// This is what makes an availability-conditional opaque result type
/// (SE-0360, `if #available` returning different types) visible offline: the
/// version it tests is written into the instruction stream as four immediates.
public struct PlatformAvailabilityCheck: Sendable, Hashable {
    public let platform: UInt32
    public let major: UInt32
    public let minor: UInt32
    public let patch: UInt32

    /// The address the thunk calls to perform the check.
    ///
    /// Kept because it is verifiable without symbols: every thunk in one image
    /// calls the same one, so a caller comparing them across thunks can tell a
    /// genuine availability check from an accidental four-immediates-then-call
    /// shape. `__isPlatformVersionAtLeast` comes from compiler-rt and is
    /// statically linked into the framework, so it carries no symbol of its own
    /// in a stripped image.
    public let checkFunctionAddress: UInt64

    public init(platform: UInt32, major: UInt32, minor: UInt32, patch: UInt32, checkFunctionAddress: UInt64) {
        self.platform = platform
        self.major = major
        self.minor = minor
        self.patch = patch
        self.checkFunctionAddress = checkFunctionAddress
    }
}

/// One answer a thunk can give, and the condition under which it gives it.
public struct ThunkCandidate: Sendable, Hashable {
    /// Which branch of the version check this candidate belongs to.
    public enum Condition: Sendable, Hashable {
        /// The thunk has no version check — this is its only answer.
        case unconditional
        /// Taken when the platform is at least the checked version.
        case availabilitySatisfied
        /// Taken otherwise.
        case availabilityNotSatisfied
    }

    /// What the address the thunk selected actually is.
    ///
    /// Both forms were measured in SwiftUI: the `csel` shape selects between
    /// two **metadata** addresses directly, while the `cbz` shape calls a
    /// metadata **accessor** in each branch and uses its result.
    public enum Reference: Sendable, Hashable {
        /// A type's metadata record. Its `…VN` symbol is exported and survives
        /// stripping, so this form usually resolves from the symbol table
        /// alone.
        case metadata(address: UInt64)
        /// A metadata accessor function; the type is whatever it returns.
        case metadataAccessor(address: UInt64)
        /// A type the branch *builds* — read symbolically by
        /// ``ThunkTypeEvaluator`` rather than looked up.
        case constructed(ThunkTypeExpression)
    }

    public let reference: Reference
    public let condition: Condition

    public init(reference: Reference, condition: Condition) {
        self.reference = reference
        self.condition = condition
    }
}

/// Why part of a thunk could not be read.
///
/// Recorded rather than swallowed: a thunk half of whose branches were
/// understood must not be presented as if it had only one answer, and the
/// reason is what tells a maintainer whether a new shape has appeared.
public enum ThunkAnalysisLimitation: Sendable, Hashable {
    /// No version check and no selection — the shape is not one of the
    /// recognized ones.
    case noRecognizedShape
    /// The version check was found, but what it selects between was not.
    case selectionNotRecognized
    /// A branch was located but neither reduces to a single lookup nor
    /// evaluates symbolically — a call it makes is one the environment does
    /// not know, or an argument it passes could not be named. The count is
    /// how many calls it makes.
    case branchIsNotASingleLookup(condition: ThunkCandidate.Condition, callCount: Int)
    /// The condition code on a `csel` is not one the analysis models, so which
    /// branch is which cannot be decided.
    case unsupportedConditionCode
}

/// What one accessor thunk was found to compute.
public struct AccessorThunkProgram: Sendable, Hashable {
    public let availabilityCheck: PlatformAvailabilityCheck?
    public let candidates: [ThunkCandidate]
    public let limitations: [ThunkAnalysisLimitation]

    public init(
        availabilityCheck: PlatformAvailabilityCheck?,
        candidates: [ThunkCandidate],
        limitations: [ThunkAnalysisLimitation]
    ) {
        self.availabilityCheck = availabilityCheck
        self.candidates = candidates
        self.limitations = limitations
    }

    /// Whether anything at all was recovered.
    public var isEmpty: Bool { candidates.isEmpty }
}

#endif
