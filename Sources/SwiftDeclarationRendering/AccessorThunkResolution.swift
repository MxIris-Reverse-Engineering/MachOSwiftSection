import Foundation
import MachOKit
import MachOSwiftSection
import Demangling
import FoundationToolbox

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

/// The generic parameters of the declaration an accessor thunk belongs to —
/// an opaque type descriptor, or the type whose field record the thunk
/// stands in — so an argument the thunk reads out of its buffer can be named
/// as that parameter.
///
/// The thunk receives one pointer: the owner's generic-argument buffer, laid
/// out as IRGen's `enumerateGenericSignatureRequirements` emits and the
/// runtime stores it — every key type parameter in signature order, then
/// every key witness table. `genericParameterKeyFlagsByDepth` records, per
/// depth, which parameters take a key argument, which is what maps the k-th
/// word back to a `(depth, index)`.
public struct AccessorThunkOwnerLayout: Sendable, Hashable {
    public let genericParameterKeyFlagsByDepth: [[Bool]]

    public init(genericParameterKeyFlagsByDepth: [[Bool]]) {
        self.genericParameterKeyFlagsByDepth = genericParameterKeyFlagsByDepth
    }

    /// No knowledge of the owner: every argument read is unnameable.
    public static let unknown = AccessorThunkOwnerLayout(genericParameterKeyFlagsByDepth: [])

    /// The layout a descriptor's generic context describes; `nil` — a
    /// non-generic owner — yields an empty layout.
    public init<Header>(genericContext: TargetGenericContext<Header>?) {
        guard let genericContext else {
            self.init(genericParameterKeyFlagsByDepth: [])
            return
        }
        // `parentParameters` is cumulative per generic ancestor, so each
        // depth's own parameters are the tail past the previous depth's
        // count; the innermost depth is `currentParameters`.
        var flagsByDepth: [[Bool]] = []
        var previousCount = 0
        for parentParameters in genericContext.parentParameters {
            flagsByDepth.append(parentParameters.dropFirst(previousCount).map(\.hasKeyArgument))
            previousCount = parentParameters.count
        }
        let ownParameters = genericContext.currentParameters
        if !ownParameters.isEmpty {
            flagsByDepth.append(ownParameters.map(\.hasKeyArgument))
        }
        self.init(genericParameterKeyFlagsByDepth: flagsByDepth)
    }

    /// The `(depth, index)` of the parameter the `keyArgumentIndex`-th word
    /// of the argument buffer carries, or `nil` when the index is past the
    /// type parameters (a witness table) or the layout is unknown.
    public func genericParameterPosition(ofKeyArgumentAt keyArgumentIndex: Int) -> (depth: Int, index: Int)? {
        var remaining = keyArgumentIndex
        for (depth, flags) in genericParameterKeyFlagsByDepth.enumerated() {
            for (index, hasKeyArgument) in flags.enumerated() where hasKeyArgument {
                if remaining == 0 { return (depth: depth, index: index) }
                remaining -= 1
            }
        }
        return nil
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
    /// `ownerLayout` names the generic parameters an argument the thunk reads
    /// stands for; pass ``AccessorThunkOwnerLayout/unknown`` when the owner
    /// is not known, and such a thunk then yields nothing rather than a
    /// half-named type.
    func underlyingTypes(forAccessorThunkAt offset: Int, in machO: MachOFile, ownerLayout: AccessorThunkOwnerLayout) -> [ConditionalUnderlyingType]
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

    /// A resolver for the current task tree only, taking precedence over
    /// ``resolver``.
    ///
    /// Exists for tests: the process-wide registration is exactly what a
    /// test must not touch, because suites run in parallel and one suite's
    /// `resolver = nil` landed in the middle of another's resolution — and,
    /// worse, its `installDisassemblingResolver()` turned every snapshot
    /// suite's kind-9 placeholders into real types for as long as it lasted.
    /// A task-local scopes the resolver to the test that set it. Read
    /// through ``effectiveResolver``.
    @TaskLocal
    public static var taskResolver: (any AccessorThunkResolving)?

    /// The resolver a rewrite uses: the task's own when one is set, else the
    /// process-wide one.
    public static var effectiveResolver: (any AccessorThunkResolving)? {
        taskResolver ?? resolver
    }
}
