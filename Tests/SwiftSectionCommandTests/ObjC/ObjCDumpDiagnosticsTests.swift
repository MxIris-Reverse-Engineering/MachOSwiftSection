import Testing
@testable import swift_section

/// `dump` used to answer three unrelated situations with the same silence:
/// empty stdout, empty stderr, exit code 0. A binary carrying no Objective-C at
/// all, a requested kind that happens to be empty, and a filter that matched
/// nothing were indistinguishable, so an unreadable binary looked exactly like
/// an uninteresting one.
///
/// The note wording is pinned here rather than by capturing a process's stderr:
/// `diagnosticNotes` is pure precisely so these cases can be enumerated cheaply.
@Suite("swift-section objc dump diagnostics")
struct ObjCDumpDiagnosticsTests {
    private static let imageDescription = "/tmp/Sample"

    private func notes(
        nameCountByKind: [ObjCSectionKind: Int],
        emittedCount: Int,
        explicitKinds: [ObjCSectionKind]? = nil,
        isEntireIndexEmpty: Bool = false,
        filter: String? = nil
    ) -> [String] {
        ObjCDumpCommand.diagnosticNotes(
            for: ObjCDumpCommand.Outcome(
                imageDescription: Self.imageDescription,
                explicitKinds: explicitKinds,
                nameCountByKind: nameCountByKind,
                isEntireIndexEmpty: isEntireIndexEmpty,
                filter: filter,
                emittedCount: emittedCount
            )
        )
    }

    @Test("A binary with no Objective-C at all says so")
    func reportsAnIndexWithNothingInIt() {
        let reported = notes(
            nameCountByKind: Dictionary(uniqueKeysWithValues: ObjCSectionKind.allCases.map { ($0, 0) }),
            emittedCount: 0,
            isEntireIndexEmpty: true
        )
        #expect(reported == ["no Objective-C metadata found in /tmp/Sample"])
    }

    /// Saying "no classes, no protocols, no categories, no structs, no unions"
    /// would be five ways of stating the one fact above.
    @Test("An empty index subsumes the per-kind notes")
    func emptyIndexSubsumesPerKindNotes() {
        let reported = notes(
            nameCountByKind: [.classes: 0, .structs: 0],
            emittedCount: 0,
            explicitKinds: [.classes, .structs],
            isEntireIndexEmpty: true
        )
        #expect(reported == ["no Objective-C metadata found in /tmp/Sample"])
    }

    @Test("An explicitly requested kind that is empty is called out")
    func reportsAnEmptyRequestedKind() {
        let reported = notes(
            nameCountByKind: [.structs: 0],
            emittedCount: 0,
            explicitKinds: [.structs]
        )
        #expect(reported == ["no structs found in /tmp/Sample"])
    }

    /// The point of tying this to `--sections`: without it, every dump of a
    /// pure-Swift binary would nag about the kinds the caller never asked for.
    @Test("Kinds that were only defaulted into are not called out")
    func staysQuietAboutDefaultedKinds() {
        let reported = notes(
            nameCountByKind: [.classes: 3, .structs: 0],
            emittedCount: 3,
            explicitKinds: nil
        )
        #expect(reported.isEmpty)
    }

    @Test("Only the empty ones among several requested kinds are called out")
    func reportsOnlyTheEmptyRequestedKinds() {
        let reported = notes(
            nameCountByKind: [.classes: 12, .structs: 0, .unions: 0],
            emittedCount: 12,
            explicitKinds: [.classes, .structs, .unions]
        )
        #expect(reported == ["no structs found in /tmp/Sample", "no unions found in /tmp/Sample"])
    }

    @Test("A filter that matched nothing reports what it was matched against")
    func reportsAFilterThatMatchedNothing() {
        let reported = notes(
            nameCountByKind: [.classes: 42],
            emittedCount: 0,
            filter: "ZZZNoSuchThing"
        )
        #expect(reported == ["--filter 'ZZZNoSuchThing' matched none of the 42 declarations in /tmp/Sample"])
    }

    @Test("The filter note agrees in number with the count it quotes")
    func filterNoteUsesTheSingularForOneDeclaration() {
        let reported = notes(
            nameCountByKind: [.classes: 1],
            emittedCount: 0,
            filter: "ZZZNoSuchThing"
        )
        #expect(reported == ["--filter 'ZZZNoSuchThing' matched none of the 1 declaration in /tmp/Sample"])
    }

    @Test("A filter that matched something is not mentioned")
    func staysQuietAboutAFilterThatMatched() {
        let reported = notes(
            nameCountByKind: [.classes: 42],
            emittedCount: 2,
            filter: "NSString"
        )
        #expect(reported.isEmpty)
    }

    /// Both notes are warranted: one says the kind is empty, the other says the
    /// filter found nothing in the kinds that were not.
    @Test("An empty kind and a missed filter are both reported")
    func reportsAnEmptyKindAlongsideAMissedFilter() {
        let reported = notes(
            nameCountByKind: [.classes: 42, .structs: 0],
            emittedCount: 0,
            explicitKinds: [.classes, .structs],
            filter: "ZZZNoSuchThing"
        )
        #expect(
            reported == [
                "no structs found in /tmp/Sample",
                "--filter 'ZZZNoSuchThing' matched none of the 42 declarations in /tmp/Sample"
            ]
        )
    }

    @Test("A dump that produced output says nothing at all")
    func staysQuietOnASuccessfulDump() {
        let reported = notes(
            nameCountByKind: [.classes: 42],
            emittedCount: 42,
            explicitKinds: [.classes]
        )
        #expect(reported.isEmpty)
    }
}
