import Foundation
import Testing
import MachOKit
import SwiftSectionFixtureSupport
@testable import MachOSwiftSection
import SwiftDeclarationRendering
@_spi(Support) @testable import SwiftPrinting
@_spi(Support) @testable import SwiftInterface
@_spi(Support) @testable import SwiftIndexing
import ObjCMetadataSource
import ObjCIndexing
import ObjCInterface
import ObjCDeclarationRendering
import Semantic

/// The two single-version outputs, each the pipeline of one subcommand.
enum InterfaceDumpKind: Sendable {
    /// `swift-section interface`: the image's Swift interface
    /// (`-FileDump.swiftinterface`, or `-ImageDump.swiftinterface` for an
    /// image read in process).
    case swiftInterface
    /// `swift-section objc dump`: every Objective-C declaration of the image
    /// (`-ObjCFileDump.h` / `-ObjCImageDump.h`).
    case objcInterface
}

/// The single-version dumps: one image — a file, an image of a dyld shared
/// cache, or an image this process loaded — run through the pipelines of
/// `swift-section interface` and `swift-section objc dump`.
///
/// A conforming suite inherits the `MachOTestingSupport` base class that
/// loads its image and passes that image to `dump(_:of:to:)`. Both outputs
/// print every comment the binary supports, so the dump carries as much as
/// the binary tells. Like its siblings this is a maintainer-inspection dump:
/// it prints / writes results without assertions.
protocol InterfaceDumpTests: InspectionDumpTests {
    /// Whether both outputs print only what the image exports — what
    /// `interface --exported-only` does, and the Objective-C header's
    /// `printExportedDeclarationsOnly` option. A suite isolated to an actor
    /// overrides it `nonisolated`.
    var printsExportedDeclarationsOnly: Bool { get }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension InterfaceDumpTests {
    var printsExportedDeclarationsOnly: Bool { false }

    var builderConfiguration: SwiftInterfaceBuilderConfiguration {
        SwiftInterfaceBuilderConfiguration(
            indexConfiguration: indexConfiguration,
            printConfiguration: .init(
                printStrippedSymbolicItem: true,
                printFieldOffset: true,
                printExpandedFieldOffsets: true,
                printMemberAddress: true,
                printVTableOffset: true,
                printPWTOffset: true,
                printExportedDeclarationsOnly: printsExportedDeclarationsOnly,
                infersObjCOverridesFromSelectorNames: true,
                usesModuleSelectors: true,
                protocolRequirementPlacement: .associatedTypes,
                memberSortOrder: .byOffset,
                printTypeLayout: true,
                printEnumLayout: true,
            ),
        )
    }

    /// Every comment an Objective-C declaration can carry: ivar offsets,
    /// property attributes, method and accessor addresses.
    var objcGenerationOptions: ObjCGenerationOptions {
        var options = ObjCGenerationOptions.default
        options.addIvarOffsetComments = true
        options.addPropertyAttributesComments = true
        options.addMethodIMPAddressComments = true
        options.addPropertyAccessorAddressComments = true
        options.printExportedDeclarationsOnly = printsExportedDeclarationsOnly
        return options
    }

    /// Runs one pipeline over `machO`, then prints the result, or writes it
    /// named after the image and the reader that read it.
    func dump<MachO: MachOFieldLayoutRenderable & ObjCMetadataSource>(
        _ kind: InterfaceDumpKind,
        of machO: MachO,
        to destination: DumpDestination
    ) async throws {
        let output: DumpOutput
        switch kind {
        case .swiftInterface:
            output = try await swiftInterface(of: machO)
        case .objcInterface:
            output = try await objcInterface(of: machO)
        }
        try deliver(output, to: destination) { file in
            try write(file.text, for: machO, suffix: file.suffix, fileExtension: file.fileExtension)
        }
    }

    /// `ImageDump` for an image read in process, `FileDump` for a file, so
    /// the file name tells which reader produced it.
    private func readerSuffix(of machO: some MachORepresentableWithCache) -> String {
        machO.asMachOImage != nil ? "ImageDump" : "FileDump"
    }

    /// The interface `swift-section interface` prints. The timed step is the
    /// indexing; printing afterwards is not timed.
    private func swiftInterface<MachO: MachOFieldLayoutRenderable>(of machO: MachO) async throws -> DumpOutput {
        let builder = try SwiftInterfaceBuilder(configuration: builderConfiguration, eventHandlers: [], in: machO)
        builder.addExtraDataProvider(SwiftInterfaceBuilderOpaqueTypeProvider(machO: machO))
        try await measuringPreparation { try await builder.prepare() }
        let interface = try await builder.printRoot().string
        return DumpOutput(
            consoleText: interface,
            files: [DumpFile(suffix: readerSuffix(of: machO), fileExtension: "swiftinterface", text: interface)]
        )
    }

    /// Every Objective-C declaration of the image, the way `objc dump`
    /// writes them to a file: classes, protocols, categories, structs and
    /// unions in that order, each kind sorted by name — the index keeps its
    /// names in dictionaries, whose order is not stable across runs — and a
    /// blank line after each.
    private func objcInterface<MachO: MachOFieldLayoutRenderable & ObjCMetadataSource>(of machO: MachO) async throws -> DumpOutput {
        let indexer = try await measuringPreparation { try await preparedObjCIndexer(of: machO) }
        let builder = ObjCInterfaceBuilder(indexer: indexer, machO: machO)
        let options = objcGenerationOptions
        let declarationKinds: [(names: [String], interface: (String) -> SemanticString?)] = [
            (indexer.classNames.sorted(), { builder.classInterface(named: $0, options: options) }),
            (indexer.protocolNames.sorted(), { builder.protocolInterface(named: $0, options: options) }),
            (indexer.categoryNames.sorted(), { builder.categoryInterface(uniqueName: $0, options: options) }),
            (indexer.structNames.sorted(), { builder.structInterface(named: $0, options: options) }),
            (indexer.unionNames.sorted(), { builder.unionInterface(named: $0, options: options) }),
        ]
        var header = ""
        for declarationKind in declarationKinds {
            for name in declarationKind.names {
                guard let interface = declarationKind.interface(name) else { continue }
                header.append(interface.string)
                header.append("\n\n")
            }
        }
        return DumpOutput(
            consoleText: header,
            files: [DumpFile(suffix: "ObjC" + readerSuffix(of: machO), fileExtension: "h", text: header)]
        )
    }
}
