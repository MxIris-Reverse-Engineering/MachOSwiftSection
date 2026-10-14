import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftPrinting
import SwiftInterface
import SwiftDeclarationRendering
@testable import MachOTestingSupport

/// The fixture's interface printed through a host's wrapper — a type that
/// forwards every read to a `MachOFile` or an in-process `MachOImage`, as
/// MachOKitUI's `MachOFileSource` / `MachOImageSource` do — must be the bytes
/// the reader itself prints.
///
/// Every comment kind and the interface header are on, so an image path, an
/// address, a field offset, a layout or a resolved opaque type that the library
/// works out only for a bare reader shows up as a difference.
///
/// The wrapper prints first. It shares the reader's per-image caches (its
/// `identifier` is the reader's), so what it builds the reader's print then
/// reads too; printed second, it could read caches the reader built and hide a
/// difference.
@Suite(.serialized)
final class WrappedReaderInterfaceTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    @Test("a wrapper of the fixture file prints the file's interface")
    func fileWrapperPrintsTheFileInterface() async throws {
        let wrapperInterface = try await Self.interface(of: ForwardingMachOReader<MachOFile, DeclaredWrapper>(machOFile))
        let fileInterface = try await Self.interface(of: machOFile)
        #expect(Self.firstDifference(between: wrapperInterface, and: fileInterface) == nil)
    }

    @Test("a wrapper of the fixture image prints the image's interface")
    func imageWrapperPrintsTheImageInterface() async throws {
        let wrapperInterface = try await Self.interface(of: ForwardingMachOReader<MachOImage, DeclaredWrapper>(machOImage))
        let imageInterface = try await Self.interface(of: machOImage)
        #expect(Self.firstDifference(between: wrapperInterface, and: imageInterface) == nil)
    }

    private static func interface<MachO: MachOFieldLayoutRenderable>(of machO: MachO) async throws -> String {
        var printConfiguration = SwiftDeclarationPrintConfiguration()
        printConfiguration.printFieldOffset = true
        printConfiguration.printExpandedFieldOffsets = true
        printConfiguration.printMemberAddress = true
        printConfiguration.printVTableOffset = true
        printConfiguration.printPWTOffset = true
        printConfiguration.printExportStatus = true
        printConfiguration.printTypeLayout = true
        printConfiguration.printEnumLayout = true
        let configuration = SwiftInterfaceBuilderConfiguration(
            printConfiguration: printConfiguration,
            interfaceHeaderInfo: InterfaceHeaderInfo(
                machO: machO,
                generatorName: "WrappedReaderInterfaceTests",
                generatorVersion: "0",
                generatedDate: Date(timeIntervalSince1970: 0)
            )
        )
        let builder = try SwiftInterfaceBuilder(configuration: configuration, eventHandlers: [], in: machO)
        builder.addExtraDataProvider(SwiftInterfaceBuilderOpaqueTypeProvider(machO: machO))
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    /// The first line the two interfaces disagree on, or `nil` when they are
    /// the same.
    private static func firstDifference(between wrapperInterface: String, and readerInterface: String) -> String? {
        let wrapperLines = wrapperInterface.components(separatedBy: "\n")
        let readerLines = readerInterface.components(separatedBy: "\n")
        for (lineIndex, (wrapperLine, readerLine)) in zip(wrapperLines, readerLines).enumerated() where wrapperLine != readerLine {
            return "line \(lineIndex + 1):\n  wrapper: \(wrapperLine)\n  reader:  \(readerLine)"
        }
        guard wrapperLines.count == readerLines.count else {
            return "the wrapper printed \(wrapperLines.count) lines, the reader \(readerLines.count)"
        }
        return nil
    }
}
