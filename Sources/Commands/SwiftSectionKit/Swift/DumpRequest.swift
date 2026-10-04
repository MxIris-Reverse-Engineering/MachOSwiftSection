import Foundation
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftDump
import Demangling
import SwiftInspection
import OutputTransformer
import SwiftOutputTransformer
import SwiftDeclarationRendering
import SwiftPrinting
import Semantic

/// A part of a binary's Swift metadata that `dump` can print.
public enum DumpSection: String, CaseIterable, Sendable, Hashable {
    case types
    case protocols
    case protocolConformances
    case associatedTypes
    /// Classes implemented through `@objc @implementation`. They have no
    /// `__swift5_*` presence; they are recognized from `__objc_classlist`
    /// joined with the symbol table.
    case objcImplementationClasses
}

/// Which stored-property offset comments `dump` and `interface` print,
/// computed statically through SwiftLayout.
public enum FieldOffsetComments: Sendable, Hashable {
    case none
    /// One comment per stored property.
    case flat
    /// Nested struct fields expanded with their absolute offsets.
    case expanded
}

/// `swift-section dump`: print the Swift declarations a binary's metadata
/// describes, section by section, as they are read.
public struct DumpRequest: Sendable, Equatable {
    public enum SectionSelection: Sendable, Hashable {
        /// Every section. One the binary does not carry is skipped silently —
        /// most binaries lack one or two.
        case all
        /// These sections, in this order. One that fails to read is reported.
        case only([DumpSection])
    }

    public enum Ordering: Sendable, Hashable {
        /// Section by section, in the order of the selection.
        case bySection
        /// Types, protocols and `@objc @implementation` classes interleaved by
        /// their offset in the binary, then conformances, then associated
        /// types.
        case binaryOrder
    }

    public var source: MachOSource
    /// Where the images a standalone binary links are looked for: by the
    /// accessor-thunk reader, the static layout engine and the ObjC ancestor
    /// chain. Named paths are consulted first; empty infers them from where
    /// the binary sits, then uses the running system's shared cache.
    public var dependencySearchPaths: [DependencySearchPath]
    public var sections: SectionSelection
    public var ordering: Ordering
    public var demangleOptions: DemangleOptions
    /// Computed statically through SwiftLayout.
    public var fieldOffsetComments: FieldOffsetComments
    public var emitsMemberAddresses: Bool
    public var emitsVTableOffsets: Bool
    public var emitsProtocolWitnessTableAddresses: Bool
    /// Size, stride and alignment, computed statically through SwiftLayout.
    public var emitsTypeLayout: Bool
    /// Strategy, per-case and spare-bit layout, computed statically through
    /// SwiftLayout.
    public var emitsEnumLayout: Bool
    /// A `not exported` comment on member lines whose symbol has no
    /// export-trie entry.
    public var emitsExportStatus: Bool
    /// A leading header comment: generator, image path, UUID, architecture,
    /// library-evolution detection, unrecoverable-facts notes.
    public var emitsHeader: Bool
    /// The comment templates. `nil` keeps the built-in rendering; a module the
    /// configuration enables also turns its comment kind on.
    public var commentTransformers: Transformer.SwiftConfiguration?
    public var destination: ProductDestination

    public init(
        source: MachOSource,
        dependencySearchPaths: [DependencySearchPath] = [],
        sections: SectionSelection = .all,
        ordering: Ordering = .bySection,
        demangleOptions: DemangleOptions = .default,
        fieldOffsetComments: FieldOffsetComments = .none,
        emitsMemberAddresses: Bool = false,
        emitsVTableOffsets: Bool = false,
        emitsProtocolWitnessTableAddresses: Bool = false,
        emitsTypeLayout: Bool = false,
        emitsEnumLayout: Bool = false,
        emitsExportStatus: Bool = false,
        emitsHeader: Bool = false,
        commentTransformers: Transformer.SwiftConfiguration? = nil,
        destination: ProductDestination = .output
    ) {
        self.source = source
        self.dependencySearchPaths = dependencySearchPaths
        self.sections = sections
        self.ordering = ordering
        self.demangleOptions = demangleOptions
        self.fieldOffsetComments = fieldOffsetComments
        self.emitsMemberAddresses = emitsMemberAddresses
        self.emitsVTableOffsets = emitsVTableOffsets
        self.emitsProtocolWitnessTableAddresses = emitsProtocolWitnessTableAddresses
        self.emitsTypeLayout = emitsTypeLayout
        self.emitsEnumLayout = emitsEnumLayout
        self.emitsExportStatus = emitsExportStatus
        self.emitsHeader = emitsHeader
        self.commentTransformers = commentTransformers
        self.destination = destination
    }

    /// Prints every declaration as it is read. A declaration that fails is
    /// reported as an ``SwiftSectionDiagnostic/Severity/error`` diagnostic in
    /// its place and the dump goes on.
    public func run(output: some SwiftSectionOutput, environment: SwiftSectionEnvironment) async throws {
        try await withAccessorThunkResolver(searchPaths: dependencySearchPaths) {
            let machOFile = try source.load()
            let session = DumpSession(output: output, destination: destination)
            try await dump(machOFile, into: session, environment: environment)
            try session.finish()
        }
    }

    private func dump(_ machOFile: MachOFile, into session: DumpSession<some SwiftSectionOutput>, environment: SwiftSectionEnvironment) async throws {
        // The ObjC ancestor chain behind the `overrides` / `explicit selector`
        // comments follows a standalone file's binds into the same images the
        // interface's indexer would use; `dump` has no indexer, so it installs
        // the resolver itself.
        ObjCAncestorResolverStore.shared.register(
            ObjCAncestorResolver(root: machOFile, searchPaths: dependencySearchPaths.indexingSearchPaths),
            for: machOFile
        )
        var configuration: DumperConfiguration = .demangleOptions(demangleOptions)
        configuration.printMemberAddress = emitsMemberAddresses
        configuration.printVTableOffset = emitsVTableOffsets
        configuration.printExportStatus = emitsExportStatus
        configuration.printConformancePWTAddress = emitsProtocolWitnessTableAddresses
        configuration.printFieldOffset = fieldOffsetComments != .none
        configuration.printTypeLayout = emitsTypeLayout
        configuration.printEnumLayout = emitsEnumLayout
        configuration.printExpandedFieldOffsets = fieldOffsetComments == .expanded
        // Without a configuration the transformer slots stay empty, keeping
        // the built-in rendering byte-for-byte identical.
        if let commentTransformers {
            configuration.applyTransformersEnablingCommentKinds(commentTransformers)
        }

        // The static (offline) field-layout path needs a SwiftLayout-backed
        // provider, built once when any layout comment is requested. Without
        // it the offline dumpers emit no layout comments, since offline
        // metadata is unavailable.
        configuration.staticLayoutDependencyResolution = dependencySearchPaths.staticLayoutDependencyResolution
        if configuration.printFieldOffset || configuration.printTypeLayout || configuration.printEnumLayout || configuration.printExpandedFieldOffsets {
            configuration.staticFieldLayoutProvider = MachOFileStaticFieldLayoutProvider(
                machOFile: machOFile,
                resolution: configuration.staticLayoutDependencyResolution
            )
        }

        if emitsHeader {
            let headerInfo = InterfaceHeaderInfo(
                machO: machOFile,
                generatorName: environment.generator.name,
                generatorVersion: environment.generator.version
            )
            await session.perform { InterfaceHeaderBlock(headerInfo) }
        }

        let isDefaultSelection: Bool
        let selectedSections: [DumpSection]
        switch sections {
        case .all:
            isDefaultSelection = true
            selectedSections = DumpSection.allCases
        case .only(let explicitSections):
            isDefaultSelection = false
            selectedSections = explicitSections
        }

        switch ordering {
        case .binaryOrder:
            try await dumpInBinaryOrder(selectedSections, isDefaultSelection: isDefaultSelection, using: configuration, in: machOFile, into: session)
        case .bySection:
            try await dumpBySection(selectedSections, isDefaultSelection: isDefaultSelection, using: configuration, in: machOFile, into: session)
        }
    }

    private func dumpBySection(
        _ selectedSections: [DumpSection],
        isDefaultSelection: Bool,
        using configuration: DumperConfiguration,
        in machOFile: MachOFile,
        into session: DumpSession<some SwiftSectionOutput>
    ) async throws {
        for section in selectedSections {
            switch section {
            case .types:
                do {
                    for type in try machOFile.swift.types {
                        try await session.dump(.type(type), using: configuration, in: machOFile)
                    }
                } catch {
                    if !isDefaultSelection {
                        session.reportError(error)
                    }
                }
            case .protocols:
                do {
                    for `protocol` in try machOFile.swift.protocols {
                        try await session.dump(.protocol(`protocol`), using: configuration, in: machOFile)
                    }
                } catch {
                    if !isDefaultSelection {
                        session.reportError(error)
                    }
                }
            case .protocolConformances:
                do {
                    for protocolConformance in try machOFile.swift.protocolConformances {
                        try await session.dump(.protocolConformance(protocolConformance), using: configuration, in: machOFile)
                    }
                } catch {
                    if !isDefaultSelection {
                        session.reportError(error)
                    }
                }
            case .associatedTypes:
                do {
                    for associatedType in try machOFile.swift.associatedTypes {
                        try await session.dump(.associatedType(associatedType), using: configuration, in: machOFile)
                    }
                } catch {
                    if !isDefaultSelection {
                        session.reportError(error)
                    }
                }
            case .objcImplementationClasses:
                let objcImplementationClasses = ObjCImplementationClass.all(in: machOFile)
                if objcImplementationClasses.isEmpty, !isDefaultSelection {
                    // Asked for explicitly and nothing there: say so, as the
                    // section-backed cases do, rather than print nothing.
                    session.write(SemanticString { Comment("No @objc @implementation classes recognized in this image.") })
                }
                for objcImplementationClass in objcImplementationClasses {
                    try await session.dump(.objcImplementationClass(objcImplementationClass), using: configuration, in: machOFile)
                }
            }
        }
    }

    private func dumpInBinaryOrder(
        _ selectedSections: [DumpSection],
        isDefaultSelection: Bool,
        using configuration: DumperConfiguration,
        in machOFile: MachOFile,
        into session: DumpSession<some SwiftSectionOutput>
    ) async throws {
        var topLevelContexts: [DumpTopLevelContext] = []
        if selectedSections.contains(.types) {
            do {
                topLevelContexts.append(contentsOf: try machOFile.swift.types.map { .type($0) })
            } catch {
                if !isDefaultSelection {
                    session.reportError(error)
                }
            }
        }

        if selectedSections.contains(.protocols) {
            do {
                topLevelContexts.append(contentsOf: try machOFile.swift.protocols.map { .protocol($0) })
            } catch {
                if !isDefaultSelection {
                    session.reportError(error)
                }
            }
        }

        if selectedSections.contains(.objcImplementationClasses) {
            topLevelContexts.append(contentsOf: ObjCImplementationClass.all(in: machOFile).map { .objcImplementationClass($0) })
        }

        topLevelContexts.sort(by: { $0.offset < $1.offset })

        if selectedSections.contains(.protocolConformances) {
            do {
                topLevelContexts.append(contentsOf: try machOFile.swift.protocolConformances.map { .protocolConformance($0) })
            } catch {
                if !isDefaultSelection {
                    session.reportError(error)
                }
            }
        }

        if selectedSections.contains(.associatedTypes) {
            do {
                topLevelContexts.append(contentsOf: try machOFile.swift.associatedTypes.map { .associatedType($0) })
            } catch {
                if !isDefaultSelection {
                    session.reportError(error)
                }
            }
        }

        for topLevelContext in topLevelContexts {
            try? await session.dump(topLevelContext, using: configuration, in: machOFile)
        }
    }
}

/// One top-level declaration of a dump, from whichever section it came.
private enum DumpTopLevelContext {
    case type(TypeContextWrapper)
    case `protocol`(MachOSwiftSection.`Protocol`)
    case protocolConformance(ProtocolConformance)
    case associatedType(AssociatedType)
    case objcImplementationClass(ObjCImplementationClass)

    var offset: Int {
        switch self {
        case .objcImplementationClass(let objcImplementationClass):
            return objcImplementationClass.offset
        case .type(let type):
            switch type {
            case .enum(let `enum`):
                return `enum`.offset
            case .struct(let `struct`):
                return `struct`.offset
            case .class(let `class`):
                return `class`.offset
            }
        case .protocol(let `protocol`):
            return `protocol`.offset
        case .associatedType(let associatedType):
            return associatedType.offset
        case .protocolConformance(let protocolConformance):
            return protocolConformance.offset
        }
    }

    var section: DumpSection {
        switch self {
        case .type:
            .types
        case .protocol:
            .protocols
        case .protocolConformance:
            .protocolConformances
        case .associatedType:
            .associatedTypes
        case .objcImplementationClass:
            .objcImplementationClasses
        }
    }

    func dump(using configuration: DumperConfiguration, in machOFile: MachOFile) async throws -> SemanticString {
        switch self {
        case .type(.enum(let `enum`)):
            try await `enum`.dump(using: configuration, in: machOFile)
        case .type(.struct(let `struct`)):
            try await `struct`.dump(using: configuration, in: machOFile)
        case .type(.class(let `class`)):
            try await `class`.dump(using: configuration, in: machOFile)
        case .protocol(let `protocol`):
            try await `protocol`.dump(using: configuration, in: machOFile)
        case .protocolConformance(let protocolConformance):
            try await protocolConformance.dump(using: configuration, in: machOFile)
        case .associatedType(let associatedType):
            try await associatedType.dump(using: configuration, in: machOFile)
        case .objcImplementationClass(let objcImplementationClass):
            try await objcImplementationClass.dump(using: configuration, in: machOFile)
        }
    }

    /// The name the dump prints for this declaration: a conformance's and an
    /// associated type's is the extended type's, as their `extension` line
    /// spells it, which for a type of this image is that type's own name.
    /// `nil` when it cannot be rendered.
    ///
    /// A conformance's line spells the type in full. The public `dumpTypeName`
    /// prints with the interface-type options instead, which drop a private
    /// type's discriminator that the type's own name keeps.
    func declaredName(using configuration: DumperConfiguration, in machOFile: MachOFile) async -> String? {
        let context = machOFile.context
        do {
            let name: SemanticString
            switch self {
            case .type(.enum(let `enum`)):
                name = try await `enum`.dumpName(using: configuration, in: context)
            case .type(.struct(let `struct`)):
                name = try await `struct`.dumpName(using: configuration, in: context)
            case .type(.class(let `class`)):
                name = try await `class`.dumpName(using: configuration, in: context)
            case .protocol(let `protocol`):
                name = try await `protocol`.dumpName(using: configuration, in: context)
            case .protocolConformance(let protocolConformance):
                name = try await protocolConformance.dumpedTypeName(isFull: true, resolver: configuration.demangleResolver, in: context)
            case .associatedType(let associatedType):
                name = try await associatedType.dumpTypeName(using: configuration, in: context)
            case .objcImplementationClass(let objcImplementationClass):
                name = try await objcImplementationClass.dumpName(using: configuration, in: context)
            }
            return name.string
        } catch {
            return nil
        }
    }
}

/// One dump in progress: where its pieces go, and — for a file destination —
/// the text collected so far.
private final class DumpSession<Output: SwiftSectionOutput> {
    let output: Output
    let destination: ProductDestination
    private var dumpedText = ""

    init(output: Output, destination: ProductDestination) {
        self.output = output
        self.destination = destination
    }

    /// Dumps one top-level declaration and hands it to the output with what it
    /// declares. Its failure is reported in its place; what throws out of here
    /// is only a failure to deliver.
    func dump(_ topLevelContext: DumpTopLevelContext, using configuration: DumperConfiguration, in machOFile: MachOFile) async throws {
        let dumpedDeclaration: SemanticString
        do {
            dumpedDeclaration = try await topLevelContext.dump(using: configuration, in: machOFile)
        } catch {
            reportError(error)
            return
        }
        switch destination {
        case .output:
            // Named only once the declaration itself rendered, and only here:
            // a file destination never hands a piece over.
            let name = await topLevelContext.declaredName(using: configuration, in: machOFile)
            output.write(.declarations(dumpedDeclaration), declaring: .swift(topLevelContext.section, name: name))
        case .file:
            write(dumpedDeclaration)
        }
    }

    func perform(@SemanticStringBuilder _ action: @Sendable () async throws -> SemanticString) async {
        do {
            write(try await action())
        } catch {
            reportError(error)
        }
    }

    func write(_ semanticString: SemanticString) {
        switch destination {
        case .output:
            output.write(.declarations(semanticString))
        case .file:
            dumpedText.append(semanticString.string)
            dumpedText.append("\n")
        }
    }

    /// A per-declaration (or per-section) failure. It reaches the output even
    /// when the dump goes to a file.
    func reportError(_ error: any Swift.Error) {
        output.reportError(error.localizedDescription)
    }

    /// Writes the collected text when the destination is a file.
    func finish() throws {
        if case .file(let path) = destination {
            try dumpedText.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        }
    }
}
