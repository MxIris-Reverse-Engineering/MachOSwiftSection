import Foundation
import Testing
import MachOKit
import SwiftDiffing
import SwiftInterface
@testable import MachOTestingSupport

/// An evolution whose versions are groups of images (evolution proposal
/// `image-group-evolution`), over `ImageGroupFixture`: one module split from
/// 2.0 on into its own image and a core image, the way SwiftUI split into
/// SwiftUI and SwiftUICore. Compared one image per version, `Gauge` would
/// read as removed in 2.0; compared as a group it stays, and its move — and
/// `calibrated()`'s, a version later — is what the evolution records.
@Suite(.serialized, ExclusiveImageAccess(ImageGroupFixture.moduleName))
struct ImageGroupEvolutionTests {
    private static let moduleName = ImageGroupFixture.moduleName
    private static let coreModuleName = ImageGroupFixture.coreModuleName
    private static let gaugeName = "\(moduleName).Gauge"
    private static let needleName = "\(coreModuleName).Needle"

    private func evolution() async throws -> ABIEvolution {
        var imageGroups: [[ABIImageSnapshot]] = []
        for images in try ImageGroupFixture.imageGroups() {
            var imageSnapshots: [ABIImageSnapshot] = []
            for image in images {
                let builder = SwiftDiffableInterfaceBuilder(in: image.machOFile)
                try await builder.prepare()
                imageSnapshots.append(ABIImageSnapshot(imageName: image.name, snapshot: builder.snapshot()))
            }
            imageGroups.append(imageSnapshots)
        }
        return try ABIEvolutionBuilder().evolution(
            ofImageGroups: imageGroups,
            versions: ImageGroupFixture.labels.map { ABIVersionDescriptor(label: $0) }
        )
    }

    private func annotatedInterfaceLines() async throws -> [String] {
        let imageGroups = try ImageGroupFixture.imageGroups().map { images in
            images.map { SwiftEvolutionInterfaceImage(imageName: $0.name, machO: $0.machOFile) }
        }
        let builder = try AnySwiftEvolutionInterfaceBuilder(imageGroups: imageGroups, labels: ImageGroupFixture.labels)
        try await builder.prepare()
        return try await builder.printAnnotatedInterface().string.components(separatedBy: "\n")
    }

    private func lineIndex(in lines: [String], where predicate: (String) -> Bool) throws -> Int {
        let index = lines.firstIndex(where: predicate)
        return try #require(index, "\(lines.joined(separator: "\n"))")
    }

    // MARK: - The evolution

    @Test("a type moved into another image of the group stays present and records the move")
    func movedTypeStaysPresent() async throws {
        let result = try await evolution()
        let gauge = try #require(result.types.first { $0.name == Self.gaugeName })
        #expect(gauge.presence == [true, true, true])
        #expect(gauge.events.isEmpty)
        #expect(gauge.imageMoves == [ImageMove(versionIndex: 1, oldImageNames: [Self.moduleName], newImageNames: [Self.coreModuleName])])
        #expect(!result.hasBreakingChange)
    }

    @Test("a member that stays behind when its type moves, and follows it a version later, moves once")
    func memberLeftBehindMovesOnce() async throws {
        let gauge = try #require(try await evolution().types.first { $0.name == Self.gaugeName })
        let calibrated = try #require(gauge.memberLineages.first { $0.latestSignature?.contains("calibrated()") == true }, "\(gauge.memberLineages)")
        #expect(calibrated.events.isEmpty)
        #expect(calibrated.imageMoves == [ImageMove(versionIndex: 2, oldImageNames: [Self.moduleName], newImageNames: [Self.coreModuleName])])
        // `reading()`, `value` and `init(value:)` moved with Gauge, `standard`
        // never left the module's image: none has a story of its own.
        #expect(gauge.memberLineages.count == 1, "\(gauge.memberLineages)")
    }

    @Test("an extension one image declares on a type another image of the group defines reads as part of the type")
    func extensionOfAGroupTypeFoldsIntoIt() async throws {
        let result = try await evolution()
        #expect(result.typeExtensions.isEmpty, "\(result.typeExtensions)")
        let needle = try #require(result.types.first { $0.name == Self.needleName })
        #expect(needle.events == [LineageEvent(versionIndex: 1, status: .added)])
    }

    @Test("every version names its images")
    func versionsNameTheirImages() async throws {
        #expect(try await evolution().versions.map(\.imageNames) == [
            [Self.moduleName],
            [Self.moduleName, Self.coreModuleName],
            [Self.moduleName, Self.coreModuleName],
        ])
    }

    // MARK: - The annotated interface

    @Test("the legend names each image with the versions holding it")
    func legendNamesTheImageGroup() async throws {
        let lines = try await annotatedInterfaceLines()
        #expect(lines.contains("// Image group:"))
        #expect(lines.contains("//   [●●●] \(Self.moduleName)"))
        #expect(lines.contains("//   [○●●] \(Self.coreModuleName)"))
    }

    @Test("the moved type keeps one body, its move annotated on the header")
    func movedTypeKeepsOneBody() async throws {
        let lines = try await annotatedInterfaceLines()
        let headerIndex = try lineIndex(in: lines) { $0.contains("struct Gauge") && !$0.hasPrefix("extension") }
        #expect(lines[headerIndex].contains("moved in 2.0: \(Self.moduleName) → \(Self.coreModuleName)"), "\(lines[headerIndex])")
        #expect(!lines.contains { $0.hasPrefix("extension \(Self.gaugeName)") }, "\(lines.joined(separator: "\n"))")
    }

    @Test("a member another image declares on the type renders in the type's body, its own move annotated")
    func memberOfAnotherImageRendersInTheBody() async throws {
        let lines = try await annotatedInterfaceLines()
        let headerIndex = try lineIndex(in: lines) { $0.contains("struct Gauge") && !$0.hasPrefix("extension") }
        let calibratedIndex = try lineIndex(in: lines) { $0.contains("func calibrated() -> Swift.Int") }
        let closingIndex = try #require(lines[headerIndex...].firstIndex(of: "}"))
        #expect(calibratedIndex > headerIndex && calibratedIndex < closingIndex)
        #expect(lines[calibratedIndex].contains("// [●●●] moved in 3.0: \(Self.moduleName) → \(Self.coreModuleName)"), "\(lines[calibratedIndex])")
        let standardIndex = try lineIndex(in: lines) { $0.contains("static var standard: \(Self.gaugeName)") }
        #expect(standardIndex > headerIndex && standardIndex < closingIndex)
        #expect(!lines[standardIndex].contains("// ["))
    }

    @Test("a cross-module extension of a type the group defines renders in that type's body")
    func crossModuleExtensionRendersInTheBody() async throws {
        let lines = try await annotatedInterfaceLines()
        let headerIndex = try lineIndex(in: lines) { $0.contains("struct Needle") && !$0.hasPrefix("extension") }
        let sweepIndex = try lineIndex(in: lines) { $0.contains("func sweep() -> Swift.Int") }
        let closingIndex = try #require(lines[headerIndex...].firstIndex(of: "}"))
        #expect(sweepIndex > headerIndex && sweepIndex < closingIndex)
        #expect(!lines.contains { $0.hasPrefix("extension \(Self.needleName)") })
    }
}
