#if THUNK_ANALYSIS

import Foundation
import MachOKit
import MachOFoundation
import Demangling
import SwiftDeclarationRendering

/// Implements the rendering layer's ``AccessorThunkResolving`` seam by reading
/// the thunk's instructions.
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

extension AccessorThunkResolution {
    /// Registers the disassembling resolver, so a kind-9 accessor reference
    /// renders as the type it stands for instead of an address.
    ///
    /// Explicit rather than automatic: registration is process-wide state, and
    /// a library that installs itself on first import leaves a host no way to
    /// opt out short of not linking it. The CLI calls this at start-up; a
    /// GUI host calls it when the user turns the feature on.
    public static func installDisassemblingResolver() {
        resolver = DisassemblingAccessorThunkResolver()
    }
}

#endif
