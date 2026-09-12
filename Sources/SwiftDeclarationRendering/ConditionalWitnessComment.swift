import Foundation
import MachOKit
import Demangling

extension PlatformAvailabilityCondition {
    /// The platform's name as `#available` spells it.
    ///
    /// The number the compiler hands `__isPlatformVersionAtLeast` is the
    /// Mach-O `PLATFORM_*` value of the target's *base* platform (Swift's
    /// `getBaseMachOPlatformID`, so a simulator build says `iOS`, and a Mac
    /// Catalyst build checks the iOS version under `PLATFORM_IOS`); `MachOKit`
    /// already owns that numbering, so the name comes from its enum and an
    /// unmodelled value stays a number rather than a guess.
    public var platformName: String {
        switch MachOKit.Platform(rawValue: platform) {
        case .macOS: "macOS"
        case .iOS: "iOS"
        case .tvOS: "tvOS"
        case .watchOS: "watchOS"
        case .bridgeOS: "bridgeOS"
        case .macCatalyst: "Mac Catalyst"
        case .iOSSimulator: "iOS Simulator"
        case .tvOSSimulator: "tvOS Simulator"
        case .watchOSSimulator: "watchOS Simulator"
        case .driverKit: "DriverKit"
        case .visionOS: "visionOS"
        case .visionOSSimulator: "visionOS Simulator"
        default: "platform \(platform)"
        }
    }

    /// `26.0`, or `26.0.1` when the patch component is set.
    public var versionText: String {
        patch == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)"
    }

    /// `macOS 26.0 or later` for the branch taken when the check passes,
    /// `before macOS 26.0` for the other one.
    public var phrase: String {
        isSatisfiedBranch ? "\(platformName) \(versionText) or later" : "before \(platformName) \(versionText)"
    }
}

/// The comment both printers put above an associated-type witness whose
/// underlying type is decided at run time (SE-0360 availability-conditional
/// opaque result type): one line per branch, each with the condition it is
/// taken under, so the `typealias` line — the newest platform's branch — is
/// not the only answer the reader sees.
public enum ConditionalWitnessComment {
    public struct Branch: Sendable, Equatable {
        /// `nil` when the thunk yields this type unconditionally.
        public let availability: PlatformAvailabilityCondition?
        /// The whole witness with this branch substituted, printed.
        public let typeText: String

        public init(availability: PlatformAvailabilityCondition?, typeText: String) {
            self.availability = availability
            self.typeText = typeText
        }
    }

    /// The comment's lines, without the `//` prefix; empty unless there is
    /// more than one branch, because a single answer is already the
    /// `typealias` line.
    public static func lines(associatedTypeName: String, branches: [Branch]) -> [String] {
        guard branches.count >= 2 else { return [] }
        let labels = branches.map { branch in (branch.availability?.phrase ?? "always") + ":" }
        let labelWidth = labels.map(\.count).max() ?? 0
        var lines = ["\(associatedTypeName) is picked at run time by an availability check (SE-0360):"]
        for (label, branch) in zip(labels, branches) {
            lines.append("  " + label.padding(toLength: labelWidth, withPad: " ", startingAt: 0) + " " + branch.typeText)
        }
        return lines
    }
}

extension Node.OpaqueTypeResolution {
    /// ``ConditionalWitnessComment/lines(associatedTypeName:branches:)`` over
    /// this resolution's branches, each printed through `resolver` so the
    /// comment spells types exactly as the `typealias` line does.
    package func conditionalWitnessCommentLines(associatedTypeName: String, resolvedBy resolver: DemangleResolver) async throws -> [String] {
        guard conditionalCandidates.count >= 2 else { return [] }
        var branches: [ConditionalWitnessComment.Branch] = []
        for candidate in conditionalCandidates {
            let typeText = try await resolver.resolve(for: candidate.substitutedNode).string
            branches.append(ConditionalWitnessComment.Branch(availability: candidate.availability, typeText: typeText))
        }
        return ConditionalWitnessComment.lines(associatedTypeName: associatedTypeName, branches: branches)
    }
}
