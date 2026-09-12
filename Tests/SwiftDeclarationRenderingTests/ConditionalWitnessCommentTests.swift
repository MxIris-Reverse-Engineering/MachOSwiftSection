import Foundation
import Testing
@testable import SwiftDeclarationRendering

/// The comment both printers put above an availability-conditional witness:
/// one line per branch with its condition, labels aligned, platform numbers
/// spelled the way `#available` does, and nothing at all for a witness with
/// a single answer.
@Suite
struct ConditionalWitnessCommentTests {
    private static let macOS: UInt32 = 1
    private static let iOS: UInt32 = 2

    private func condition(platform: UInt32 = macOS, major: UInt32 = 26, minor: UInt32 = 0, patch: UInt32 = 0, isSatisfiedBranch: Bool) -> PlatformAvailabilityCondition {
        PlatformAvailabilityCondition(platform: platform, major: major, minor: minor, patch: patch, isSatisfiedBranch: isSatisfiedBranch)
    }

    @Test func everyBranchGetsALineWithItsCondition() {
        let lines = ConditionalWitnessComment.lines(
            associatedTypeName: "Body",
            branches: [
                ConditionalWitnessComment.Branch(availability: condition(isSatisfiedBranch: true), typeText: "M.Box<M.Static>"),
                ConditionalWitnessComment.Branch(availability: condition(isSatisfiedBranch: false), typeText: "M.Box<M.Dynamic>"),
            ]
        )
        #expect(lines == [
            "Body is picked at run time by an availability check (SE-0360):",
            "  macOS 26.0 or later: M.Box<M.Static>",
            "  before macOS 26.0:   M.Box<M.Dynamic>",
        ])
    }

    @Test func aSingleAnswerNeedsNoComment() {
        let lines = ConditionalWitnessComment.lines(
            associatedTypeName: "Body",
            branches: [ConditionalWitnessComment.Branch(availability: nil, typeText: "M.Box<M.Static>")]
        )
        #expect(lines.isEmpty)
        #expect(ConditionalWitnessComment.lines(associatedTypeName: "Body", branches: []).isEmpty)
    }

    @Test func anUnconditionalBranchIsLabelledAlways() {
        let lines = ConditionalWitnessComment.lines(
            associatedTypeName: "Body",
            branches: [
                ConditionalWitnessComment.Branch(availability: condition(platform: Self.iOS, major: 18, minor: 4, patch: 1, isSatisfiedBranch: true), typeText: "A"),
                ConditionalWitnessComment.Branch(availability: nil, typeText: "B"),
            ]
        )
        #expect(lines[1] == "  iOS 18.4.1 or later: A")
        #expect(lines[2] == "  always:              B")
    }

    @Test func platformNumbersFollowTheMachOPlatformEnumeration() {
        #expect(condition(platform: 1, isSatisfiedBranch: true).platformName == "macOS")
        #expect(condition(platform: 2, isSatisfiedBranch: true).platformName == "iOS")
        #expect(condition(platform: 3, isSatisfiedBranch: true).platformName == "tvOS")
        #expect(condition(platform: 4, isSatisfiedBranch: true).platformName == "watchOS")
        #expect(condition(platform: 11, isSatisfiedBranch: true).platformName == "visionOS")
        #expect(condition(platform: 99, isSatisfiedBranch: true).platformName == "platform 99")
    }

    @Test func thePatchComponentPrintsOnlyWhenSet() {
        #expect(condition(major: 26, minor: 0, patch: 0, isSatisfiedBranch: true).versionText == "26.0")
        #expect(condition(major: 26, minor: 1, patch: 2, isSatisfiedBranch: false).phrase == "before macOS 26.1.2")
    }
}
