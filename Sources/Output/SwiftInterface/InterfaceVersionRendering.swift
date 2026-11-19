import Foundation
import SwiftDeclaration
@_spi(Support) import SwiftIndexing
@_spi(Support) import SwiftPrinting
import SwiftDeclarationRendering
import SwiftDiffing
import MachOSwiftSection
import Semantic
import OrderedCollections
import SwiftStdlibToolbox
import Demangling

/// One version of the module under comparison, erased over its reader type.
///
/// `InterfaceUnionWalker` consumes every version through this seam, which is
/// what lets both union renderers stay reader-agnostic: the evolution
/// builder's homogeneous-array and parameter-pack initializers collapse their
/// N inputs into `[any InterfaceVersionRendering]`, and the two-sided diff
/// renderer wraps its `old`/`new` builders into a 2-element axis the same way.
/// The erasure is lossless because the walker only ever consumes a printer as
/// "render this member to a `SemanticString`" — no `MachO`-typed value crosses
/// the seam.
///
/// A version made up of a group of images (evolution proposal
/// `image-group-evolution`) is one unit per image behind the same seam: its
/// model is the images' declarations together, and the walker asks it which
/// image renders each definition, since a printer reads facts from the image
/// it was built for.
protocol InterfaceVersionRendering: Sendable {
    /// The version's indexing/printing event dispatcher, for reporting header
    /// print failures on the side that failed.
    var eventDispatcher: SwiftIndexEvents.Dispatcher { get }

    /// Index the binary and force full member indexing
    /// (`SwiftDiffableInterfaceBuilder.prepare()`).
    func prepare() async throws

    /// Freeze the prepared model into the `ABISnapshot` currency
    /// `ABIEvolutionBuilder` consumes, one per image under its name — a
    /// single one for a version of one image.
    func imageSnapshots() -> [ABIImageSnapshot]

    // MARK: Model access (plain declaration-model values, reader-free)

    var rootTypeDefinitions: [TypeDefinition] { get }
    var rootProtocolDefinitions: [ProtocolDefinition] { get }
    var typeExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> { get }
    var protocolExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> { get }
    var typeAliasExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> { get }
    var conformanceExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> { get }
    var globalVariableDefinitions: [VariableDefinition] { get }
    var globalFunctionDefinitions: [FunctionDefinition] { get }

    // MARK: Routing

    /// The unit whose printer renders `definition` and its members: this
    /// one, or — for a version made up of a group of images — the unit of
    /// the image that indexed it.
    func renderingUnit(for definition: some Definition) -> any InterfaceVersionRendering

    /// The units whose globals the version lists, one per image, each
    /// rendering its own.
    var globalRenderingUnits: [any InterfaceVersionRendering] { get }

    /// The plain extensions of `typeDefinition` (no conformance, no `where`
    /// clause) that another image of the version's group declares. They
    /// render in the type's body, where an evolution over the group counts
    /// their members; empty for a version of one image.
    func foldedExtensionDefinitions(of typeDefinition: TypeDefinition) -> [ExtensionDefinition]

    // MARK: Erased printing (each call renders with this version's printer)

    func printTypeHeader(_ typeDefinition: TypeDefinition, level: Int) async throws -> SemanticString
    func printProtocolHeader(_ protocolDefinition: ProtocolDefinition, level: Int) async throws -> SemanticString
    func printVariable(_ variable: VariableDefinition, level: Int) async -> SemanticString
    func printFunction(_ function: FunctionDefinition, level: Int) async -> SemanticString
    func printSubscript(_ subscriptDefinition: SubscriptDefinition, level: Int) async -> SemanticString
    func printField(_ field: FieldDefinition, level: Int) async -> SemanticString
    func printEnumCase(_ field: FieldDefinition, level: Int) async -> SemanticString
    func printDeinit() -> SemanticString
    func printAssociatedType(_ name: String) -> SemanticString
}

/// The one concrete `InterfaceVersionRendering`: a per-version
/// `SwiftDiffableInterfaceBuilder` plus a printer sharing that builder's event
/// dispatcher — so the handlers the host passed to the builder cover printing
/// too. (Printers constructed with the bare `.init(in:)` have no sink at all,
/// which once left the whole diff path dropping failures silently — the very
/// silence the header-failure reporting exists to end.)
final class InterfaceVersionUnit<MachO: MachOFieldLayoutRenderable>: InterfaceVersionRendering {
    private let builder: SwiftDiffableInterfaceBuilder<MachO>
    private let printer: SwiftDeclarationPrinter<MachO>

    /// The image's name on the axis when it is one image of a group
    /// (evolution proposal `image-group-evolution`); `nil` otherwise.
    let imageName: String?

    /// Wraps an already-constructed (typically already-prepared) builder —
    /// the diff renderer's construction path, where the caller hands over two
    /// prepared builders.
    init(builder: SwiftDiffableInterfaceBuilder<MachO>, imageName: String? = nil) {
        self.builder = builder
        self.printer = .init(eventDispatcher: builder.indexer.eventDispatcher, in: builder.machO)
        self.imageName = imageName
    }

    /// Builds the version's own builder — the evolution builder's construction
    /// path, where each version arrives as a bare reader.
    convenience init(
        configuration: SwiftDeclarationIndexConfiguration,
        eventHandlers: [SwiftIndexEvents.Handler],
        machO: MachO,
        imageName: String? = nil
    ) {
        self.init(builder: SwiftDiffableInterfaceBuilder(configuration: configuration, eventHandlers: eventHandlers, in: machO), imageName: imageName)
    }

    var eventDispatcher: SwiftIndexEvents.Dispatcher { builder.indexer.eventDispatcher }

    func prepare() async throws {
        try await builder.prepare()
    }

    func imageSnapshots() -> [ABIImageSnapshot] {
        [ABIImageSnapshot(imageName: imageName ?? "", snapshot: builder.snapshot())]
    }

    func renderingUnit(for definition: some Definition) -> any InterfaceVersionRendering {
        self
    }

    var globalRenderingUnits: [any InterfaceVersionRendering] { [self] }

    func foldedExtensionDefinitions(of typeDefinition: TypeDefinition) -> [ExtensionDefinition] {
        []
    }

    /// Every type the image defines, nested ones included.
    var allTypeDefinitions: [TypeDefinition] { Array(builder.indexer.allTypeDefinitions.values) }

    /// Every protocol the image defines, nested ones included.
    var allProtocolDefinitions: [ProtocolDefinition] { Array(builder.indexer.allProtocolDefinitions.values) }

    var rootTypeDefinitions: [TypeDefinition] { Array(builder.indexer.rootTypeDefinitions.values) }
    var rootProtocolDefinitions: [ProtocolDefinition] { Array(builder.indexer.rootProtocolDefinitions.values) }
    var typeExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> { builder.indexer.typeExtensionDefinitions }
    var protocolExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> { builder.indexer.protocolExtensionDefinitions }
    var typeAliasExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> { builder.indexer.typeAliasExtensionDefinitions }
    var conformanceExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> { builder.indexer.conformanceExtensionDefinitions }
    var globalVariableDefinitions: [VariableDefinition] { builder.indexer.globalVariableDefinitions }
    var globalFunctionDefinitions: [FunctionDefinition] { builder.indexer.globalFunctionDefinitions }

    func printTypeHeader(_ typeDefinition: TypeDefinition, level: Int) async throws -> SemanticString {
        try await printer.printTypeHeader(typeDefinition, level: level)
    }

    func printProtocolHeader(_ protocolDefinition: ProtocolDefinition, level: Int) async throws -> SemanticString {
        try await printer.printProtocolHeader(protocolDefinition, level: level)
    }

    func printVariable(_ variable: VariableDefinition, level: Int) async -> SemanticString {
        await printer.printVariable(variable, level: level)
    }

    func printFunction(_ function: FunctionDefinition, level: Int) async -> SemanticString {
        await printer.printFunction(function, level: level)
    }

    func printSubscript(_ subscriptDefinition: SubscriptDefinition, level: Int) async -> SemanticString {
        await printer.printSubscript(subscriptDefinition, level: level)
    }

    func printField(_ field: FieldDefinition, level: Int) async -> SemanticString {
        await printer.printField(field, level: level)
    }

    func printEnumCase(_ field: FieldDefinition, level: Int) async -> SemanticString {
        await printer.printEnumCase(field, level: level)
    }

    func printDeinit() -> SemanticString {
        printer.printDeinit()
    }

    func printAssociatedType(_ name: String) -> SemanticString {
        printer.printAssociatedType(name)
    }
}

/// One version made up of a group of images (evolution proposal
/// `image-group-evolution`): an `InterfaceVersionUnit` per image, its model
/// the images' declarations together, and every definition rendered by the
/// unit of the image that indexed it — a printer reads facts from the image
/// it was built for.
///
/// A plain extension (no conformance, no `where` clause) one image declares
/// on a type the group defines folds into the type, as the evolution over
/// the group counts its members there: it leaves the extension buckets and
/// renders in the type's body through `foldedExtensionDefinitions(of:)`.
final class InterfaceVersionGroupUnit<MachO: MachOFieldLayoutRenderable>: InterfaceVersionRendering {
    /// In the group's order, the primary image first.
    private let imageUnits: [InterfaceVersionUnit<MachO>]

    let eventDispatcher: SwiftIndexEvents.Dispatcher

    /// Which image indexed each definition, and the plain extensions folded
    /// into the types the group defines; built once the images are prepared.
    private struct Routing {
        var imageIndexByDefinition: [ObjectIdentifier: Int] = [:]
        var foldedExtensionsByTypeKey: [ABIKey: [ExtensionDefinition]] = [:]
        var foldedExtensionIdentifiers: Set<ObjectIdentifier> = []
    }

    @Mutex
    private var routing: Routing = Routing()

    init(configuration: SwiftDeclarationIndexConfiguration, eventHandlers: [SwiftIndexEvents.Handler], images: [(imageName: String, machO: MachO)]) {
        self.imageUnits = images.map { image in
            InterfaceVersionUnit(configuration: configuration, eventHandlers: eventHandlers, machO: image.machO, imageName: image.imageName)
        }
        if let primaryUnit = imageUnits.first {
            self.eventDispatcher = primaryUnit.eventDispatcher
        } else {
            // A version holding no image still reports through the host's
            // handlers.
            let eventDispatcher = SwiftIndexEvents.Dispatcher()
            eventDispatcher.addHandlers(eventHandlers)
            self.eventDispatcher = eventDispatcher
        }
    }

    func prepare() async throws {
        for imageUnit in imageUnits {
            try await imageUnit.prepare()
        }
        var routing = Routing()
        var typeKeys: Set<ABIKey> = []
        for (imageIndex, imageUnit) in imageUnits.enumerated() {
            for typeDefinition in imageUnit.allTypeDefinitions {
                routing.imageIndexByDefinition[ObjectIdentifier(typeDefinition)] = imageIndex
                typeKeys.insert(ABIKey.makeUnwrappingType(for: typeDefinition.typeName.node))
            }
            for protocolDefinition in imageUnit.allProtocolDefinitions {
                routing.imageIndexByDefinition[ObjectIdentifier(protocolDefinition)] = imageIndex
            }
            for bucket in [
                imageUnit.typeExtensionDefinitions,
                imageUnit.protocolExtensionDefinitions,
                imageUnit.typeAliasExtensionDefinitions,
                imageUnit.conformanceExtensionDefinitions,
            ] {
                for extensionDefinitions in bucket.values {
                    for extensionDefinition in extensionDefinitions {
                        routing.imageIndexByDefinition[ObjectIdentifier(extensionDefinition)] = imageIndex
                    }
                }
            }
        }
        // The same rule the evolution folds by (`MergedImageGroup`): the
        // target keyed as the differ keys a type, the extension plain.
        for imageUnit in imageUnits {
            for (extensionName, extensionDefinitions) in imageUnit.typeExtensionDefinitions {
                let targetKey = ABIKey.makeUnwrappingType(for: extensionName.node)
                guard typeKeys.contains(targetKey) else { continue }
                for extensionDefinition in extensionDefinitions
                    where extensionDefinition.conformingProtocolName == nil && extensionDefinition.genericSignature == nil && !extensionDefinition.isRetroactive {
                    routing.foldedExtensionsByTypeKey[targetKey, default: []].append(extensionDefinition)
                    routing.foldedExtensionIdentifiers.insert(ObjectIdentifier(extensionDefinition))
                }
            }
        }
        self.routing = routing
    }

    func imageSnapshots() -> [ABIImageSnapshot] {
        imageUnits.flatMap { $0.imageSnapshots() }
    }

    var rootTypeDefinitions: [TypeDefinition] { imageUnits.flatMap(\.rootTypeDefinitions) }
    var rootProtocolDefinitions: [ProtocolDefinition] { imageUnits.flatMap(\.rootProtocolDefinitions) }
    var typeExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> {
        Self.merged(imageUnits.map(\.typeExtensionDefinitions), excluding: routing.foldedExtensionIdentifiers)
    }
    var protocolExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> {
        Self.merged(imageUnits.map(\.protocolExtensionDefinitions), excluding: [])
    }
    var typeAliasExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> {
        Self.merged(imageUnits.map(\.typeAliasExtensionDefinitions), excluding: [])
    }
    var conformanceExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> {
        Self.merged(imageUnits.map(\.conformanceExtensionDefinitions), excluding: [])
    }
    var globalVariableDefinitions: [VariableDefinition] { imageUnits.flatMap(\.globalVariableDefinitions) }
    var globalFunctionDefinitions: [FunctionDefinition] { imageUnits.flatMap(\.globalFunctionDefinitions) }

    /// One extension bucket of every image, merged by name in the group's
    /// order — two images extending one type list under one name, as the
    /// evolution merges them into one container.
    private static func merged(
        _ buckets: [OrderedDictionary<ExtensionName, [ExtensionDefinition]>],
        excluding excludedIdentifiers: Set<ObjectIdentifier>
    ) -> OrderedDictionary<ExtensionName, [ExtensionDefinition]> {
        var merged: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:]
        for bucket in buckets {
            for (extensionName, extensionDefinitions) in bucket {
                let keptDefinitions = extensionDefinitions.filter { !excludedIdentifiers.contains(ObjectIdentifier($0)) }
                guard !keptDefinitions.isEmpty else { continue }
                merged[extensionName, default: []].append(contentsOf: keptDefinitions)
            }
        }
        return merged
    }

    func renderingUnit(for definition: some Definition) -> any InterfaceVersionRendering {
        // Every definition the walker reaches comes from one of the images;
        // the primary image's unit answers for one the routing missed.
        imageUnits[routing.imageIndexByDefinition[ObjectIdentifier(definition)] ?? 0]
    }

    var globalRenderingUnits: [any InterfaceVersionRendering] { imageUnits }

    func foldedExtensionDefinitions(of typeDefinition: TypeDefinition) -> [ExtensionDefinition] {
        routing.foldedExtensionsByTypeKey[ABIKey.makeUnwrappingType(for: typeDefinition.typeName.node)] ?? []
    }

    func printTypeHeader(_ typeDefinition: TypeDefinition, level: Int) async throws -> SemanticString {
        try await renderingUnit(for: typeDefinition).printTypeHeader(typeDefinition, level: level)
    }

    func printProtocolHeader(_ protocolDefinition: ProtocolDefinition, level: Int) async throws -> SemanticString {
        try await renderingUnit(for: protocolDefinition).printProtocolHeader(protocolDefinition, level: level)
    }

    // A member renders through the unit `renderingUnit(for:)` gives its
    // definition; the walker never asks the group itself. Asked anyway, the
    // primary image renders it.

    func printVariable(_ variable: VariableDefinition, level: Int) async -> SemanticString {
        await imageUnits.first?.printVariable(variable, level: level) ?? SemanticString()
    }

    func printFunction(_ function: FunctionDefinition, level: Int) async -> SemanticString {
        await imageUnits.first?.printFunction(function, level: level) ?? SemanticString()
    }

    func printSubscript(_ subscriptDefinition: SubscriptDefinition, level: Int) async -> SemanticString {
        await imageUnits.first?.printSubscript(subscriptDefinition, level: level) ?? SemanticString()
    }

    func printField(_ field: FieldDefinition, level: Int) async -> SemanticString {
        await imageUnits.first?.printField(field, level: level) ?? SemanticString()
    }

    func printEnumCase(_ field: FieldDefinition, level: Int) async -> SemanticString {
        await imageUnits.first?.printEnumCase(field, level: level) ?? SemanticString()
    }

    func printDeinit() -> SemanticString {
        imageUnits.first?.printDeinit() ?? SemanticString()
    }

    func printAssociatedType(_ name: String) -> SemanticString {
        imageUnits.first?.printAssociatedType(name) ?? SemanticString()
    }
}
