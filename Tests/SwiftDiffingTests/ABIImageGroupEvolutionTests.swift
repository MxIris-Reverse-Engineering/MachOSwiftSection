@testable import SwiftDiffing
import Testing
import Foundation

// MARK: - Versions made up of groups of images
//
// Evolution proposal `image-group-evolution`: a module Apple split across
// images — SwiftUI and SwiftUICore — keeps one API surface, and a
// declaration moved between the images keeps its mangled name. Driven with
// hand-built snapshots, like the other `ABIEvolutionBuilder` suites, so each
// rule is pinned without a Mach-O.

private func record(_ identity: String, isExported: Bool? = true) -> MemberRecord {
    MemberRecord(identityKey: .mangled(identity), payloadKey: .mangled(identity), kind: .function, signature: identity, isExported: isExported)
}

private func typeContainer(_ name: String, members: [MemberRecord] = []) -> ContainerSnapshot {
    ContainerSnapshot(key: .mangled(name), name: name, kind: .type, members: members)
}

/// An extension of `typeName` with no conformance, no `where` clause and not
/// retroactive, keyed as the differ keys a struct's.
private func plainExtension(of typeName: String, members: [MemberRecord]) -> ContainerSnapshot {
    ContainerSnapshot(
        key: ABIDiffer.extensionContainerKey(
            kindToken: "struct",
            targetSortKey: ABIKey.mangled(typeName).sortKey,
            protocolSortKey: nil,
            whereSortKey: nil,
            isRetroactive: false
        ),
        name: typeName,
        kind: .typeExtension,
        members: members
    )
}

private func protocolExtension(of protocolName: String, members: [MemberRecord]) -> ContainerSnapshot {
    ContainerSnapshot(key: .printed("extbucket:protocol|\(protocolName)"), name: protocolName, kind: .protocolExtension, members: members)
}

private func image(
    _ name: String,
    types: [ContainerSnapshot] = [],
    typeExtensions: [ContainerSnapshot] = [],
    protocolExtensions: [ContainerSnapshot] = [],
    hasLocalSwiftSymbols: Bool = true
) -> ABIImageSnapshot {
    ABIImageSnapshot(
        imageName: name,
        snapshot: ABISnapshot(types: types, typeExtensions: typeExtensions, protocolExtensions: protocolExtensions, hasLocalSwiftSymbols: hasLocalSwiftSymbols)
    )
}

private func evolution(_ imageGroups: [[ABIImageSnapshot]]) throws -> ABIEvolution {
    try ABIEvolutionBuilder().evolution(
        ofImageGroups: imageGroups,
        versions: imageGroups.indices.map { ABIVersionDescriptor(label: "\($0 + 1).0") }
    )
}

@Suite("ABIEvolutionBuilder: versions made up of groups of images")
struct ABIImageGroupEvolutionTests {
    @Test("a type that moves between the images of a group stays present and records its move")
    func typeMoveIsNoRemoval() throws {
        let result = try evolution([
            [image("SwiftUI", types: [typeContainer("Text", members: [record("body")])])],
            [image("SwiftUI"), image("SwiftUICore", types: [typeContainer("Text", members: [record("body")])])],
        ])
        let lineage = try #require(result.types.first { $0.name == "Text" })
        #expect(lineage.events.isEmpty)
        #expect(lineage.presence == [true, true])
        #expect(lineage.imageMoves == [ImageMove(versionIndex: 1, oldImageNames: ["SwiftUI"], newImageNames: ["SwiftUICore"])])
        #expect(!result.hasBreakingChange)
    }

    @Test("a member that moves with its type records no move of its own")
    func memberMovingWithItsTypeIsTheTypesMove() throws {
        let result = try evolution([
            [image("SwiftUI", types: [typeContainer("Text", members: [record("body")])])],
            [image("SwiftUI"), image("SwiftUICore", types: [typeContainer("Text", members: [record("body")])])],
        ])
        let lineage = try #require(result.types.first { $0.name == "Text" })
        #expect(lineage.memberLineages.isEmpty)
    }

    @Test("a member another image declares in a plain extension belongs to its type, and stays where it was declared")
    func plainExtensionFoldsIntoItsType() throws {
        let result = try evolution([
            [image("SwiftUI", types: [typeContainer("Gauge", members: [record("reading"), record("calibrated")])])],
            [
                image("SwiftUI", typeExtensions: [plainExtension(of: "Gauge", members: [record("calibrated")])]),
                image("SwiftUICore", types: [typeContainer("Gauge", members: [record("reading")])]),
            ],
        ])
        #expect(result.typeExtensions.isEmpty)
        let lineage = try #require(result.types.first { $0.name == "Gauge" })
        #expect(lineage.events.isEmpty)
        #expect(lineage.imageMoves == [ImageMove(versionIndex: 1, oldImageNames: ["SwiftUI"], newImageNames: ["SwiftUICore"])])
        // `calibrated` stayed in SwiftUI and `reading` moved with its type:
        // neither has a story of its own.
        #expect(lineage.memberLineages.isEmpty)
    }

    @Test("a member that moves without its container records its own move")
    func memberMovesOnItsOwn() throws {
        let result = try evolution([
            [
                image("SwiftUI", typeExtensions: [plainExtension(of: "Gauge", members: [record("calibrated")])]),
                image("SwiftUICore", types: [typeContainer("Gauge", members: [record("reading")])]),
            ],
            [image("SwiftUI"), image("SwiftUICore", types: [typeContainer("Gauge", members: [record("reading"), record("calibrated")])])],
        ])
        let lineage = try #require(result.types.first { $0.name == "Gauge" })
        #expect(lineage.imageMoves == nil)
        let calibrated = try #require(lineage.memberLineages.first { $0.key == .mangled("calibrated") })
        #expect(calibrated.events.isEmpty)
        #expect(calibrated.latestSignature == "calibrated")
        #expect(calibrated.imageMoves == [ImageMove(versionIndex: 1, oldImageNames: ["SwiftUI"], newImageNames: ["SwiftUICore"])])
    }

    @Test("two images extending one protocol make one extension, and a member moving between them is recorded")
    func extensionsOfTwoImagesMerge() throws {
        let result = try evolution([
            [image("SwiftUI", protocolExtensions: [protocolExtension(of: "View", members: [record("padding"), record("toolbar")])])],
            [
                image("SwiftUI", protocolExtensions: [protocolExtension(of: "View", members: [record("toolbar")])]),
                image("SwiftUICore", protocolExtensions: [protocolExtension(of: "View", members: [record("padding")])]),
            ],
        ])
        let lineage = try #require(result.protocolExtensions.first { $0.name == "View" })
        #expect(lineage.events.isEmpty)
        #expect(lineage.imageMoves == [ImageMove(versionIndex: 1, oldImageNames: ["SwiftUI"], newImageNames: ["SwiftUI", "SwiftUICore"])])
        let padding = try #require(lineage.memberLineages.first { $0.key == .mangled("padding") })
        #expect(padding.events.isEmpty)
        #expect(padding.imageMoves == [ImageMove(versionIndex: 1, oldImageNames: ["SwiftUI"], newImageNames: ["SwiftUICore"])])
        // `toolbar` stayed in SwiftUI while its extension gained an image.
        #expect(!lineage.memberLineages.contains { $0.key == .mangled("toolbar") })
        #expect(result.keyCollisionsByVersion == nil)
    }

    @Test("a declaration two images both define is compared once, and the dropped one names its image")
    func duplicateAcrossImagesNamesItsImage() throws {
        let result = try evolution([
            [image("AppKit", types: [typeContainer("Shared")])],
            [image("AppKit", types: [typeContainer("Shared")]), image("UIFoundation", types: [typeContainer("Shared")])],
        ])
        let collisions = try #require(result.keyCollisionsByVersion)
        #expect(collisions[0].isEmpty)
        #expect(collisions[1] == [ABIKeyCollision(key: .mangled("Shared"), containerName: nil, droppedSignatures: ["Shared"], droppedImageNames: ["UIFoundation"])])
    }

    @Test("a move across versions that could not show the member is placed between the observations around them")
    func moveAcrossHiddenVersions() throws {
        let result = try evolution([
            [image("SwiftUI", types: [typeContainer("Gauge", members: [record("calibrated", isExported: false)])])],
            [image("SwiftUI", types: [typeContainer("Gauge")], hasLocalSwiftSymbols: false)],
            [
                image("SwiftUI", types: [typeContainer("Gauge")]),
                image("SwiftUICore", typeExtensions: [plainExtension(of: "Gauge", members: [record("calibrated", isExported: false)])]),
            ],
        ])
        let lineage = try #require(result.types.first { $0.name == "Gauge" })
        let calibrated = try #require(lineage.memberLineages.first { $0.key == .mangled("calibrated") })
        #expect(calibrated.presenceStates == [.present, .inferredPresent, .present])
        #expect(calibrated.imageMoves == [ImageMove(versionIndex: 2, oldImageNames: ["SwiftUI"], newImageNames: ["SwiftUICore"], earliestVersionIndex: 1)])
        #expect(calibrated.imageMoves?.first?.phrase(on: result.versions) == "moved between 1.0 and 3.0: SwiftUI → SwiftUICore")
    }

    @Test("a version hides non-exported members when any image of its group lacks local Swift symbols")
    func anyStrippedImageHidesTheVersionsNonExportedMembers() throws {
        let result = try evolution([
            [image("SwiftUI", types: [typeContainer("Gauge", members: [record("calibrated", isExported: false)])])],
            [image("SwiftUI", types: [typeContainer("Gauge")]), image("SwiftUICore", hasLocalSwiftSymbols: false)],
            [image("SwiftUI", types: [typeContainer("Gauge", members: [record("calibrated", isExported: false)])])],
        ])
        #expect(result.versionIndicesWithoutLocalSwiftSymbols == [1])
        let lineage = try #require(result.types.first { $0.name == "Gauge" })
        let calibrated = try #require(lineage.memberLineages.first { $0.key == .mangled("calibrated") })
        #expect(calibrated.events.isEmpty)
        #expect(calibrated.presenceStates == [.present, .inferredPresent, .present])
    }

    @Test("each version names the images of its group, an empty group holding nothing")
    func versionsNameTheirImages() throws {
        let result = try evolution([
            [],
            [image("AppKit", types: [typeContainer("NSView")]), image("UIFoundation")],
        ])
        #expect(result.versions.map(\.imageNames) == [[], ["AppKit", "UIFoundation"]])
        let lineage = try #require(result.types.first { $0.name == "NSView" })
        #expect(lineage.events == [LineageEvent(versionIndex: 1, status: .added)])
        #expect(result.imagePresences == [
            ImagePresence(imageName: "AppKit", presence: [false, true]),
            ImagePresence(imageName: "UIFoundation", presence: [false, true]),
        ])
    }

    @Test("an evolution of one image per version names no images and records no moves in its JSON")
    func oneImagePerVersionKeepsItsJSON() throws {
        let result = try ABIEvolutionBuilder().evolution(
            of: [ABISnapshot(types: [typeContainer("Text")]), ABISnapshot(types: [typeContainer("Text"), typeContainer("Label")])],
            versions: [ABIVersionDescriptor(label: "1.0"), ABIVersionDescriptor(label: "2.0")]
        )
        let json = String(decoding: try ABIJSON.encoder().encode(result), as: UTF8.self)
        #expect(!json.contains("imageNames"))
        #expect(!json.contains("imageMoves"))
        #expect(result.imagePresences == nil)
    }
}

@Suite("ABIEvolutionReporter: versions made up of groups of images")
struct ABIImageGroupEvolutionReportTests {
    private func splitReport() throws -> String {
        ABIEvolutionReporter().report(try evolution([
            [image("SwiftUI", types: [typeContainer("Text", members: [record("body")])])],
            [image("SwiftUI"), image("SwiftUICore", types: [typeContainer("Text", members: [record("body")])])],
        ]))
    }

    @Test("the header names each image with the versions holding it")
    func headerNamesTheImageGroup() throws {
        #expect(try splitReport().hasPrefix("""
        ABI evolution across 2 versions: 1.0 → 2.0
        Image group:
          [●●] SwiftUI
          [○●] SwiftUICore
        """))
    }

    @Test("a move reads among the declaration's events")
    func moveReadsAmongTheEvents() throws {
        #expect(try splitReport().contains("""
          [●●] Text
              > moved in 2.0: SwiftUI → SwiftUICore
        """))
    }

    @Test("the transition summary counts moves without letting them weigh on the verdict")
    func summaryCountsMoves() throws {
        #expect(try splitReport().contains("  1.0 → 2.0: 1 moved · additive"))
    }

    @Test("a dropped duplicate names its image")
    func droppedDuplicateNamesItsImage() throws {
        let report = ABIEvolutionReporter().report(try evolution([
            [image("AppKit", types: [typeContainer("Shared")])],
            [image("AppKit", types: [typeContainer("Shared")]), image("UIFoundation", types: [typeContainer("Shared")])],
        ]))
        #expect(report.contains("  2.0 · dropped: Shared (UIFoundation)"))
    }
}
