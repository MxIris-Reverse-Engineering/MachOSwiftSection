import Foundation
import SwiftDeclaration
@_spi(Support) import SwiftIndexing
@_spi(Support) import SwiftPrinting
import SwiftDeclarationRendering
import SwiftDiffing
import MachOSwiftSection
import Semantic
import OrderedCollections

/// One version on the evolution axis, erased over its reader type.
///
/// `SwiftEvolutionInterfaceRenderer` consumes N versions through this seam so
/// the public `SwiftEvolutionInterfaceBuilder` can stay non-generic: the
/// homogeneous-array and parameter-pack initializers both collapse their inputs
/// into `[any EvolutionVersionRendering]`. The erasure is lossless because the
/// renderer only ever consumes a printer as "render this member to a
/// `SemanticString`" — no `MachO`-typed value crosses the seam.
protocol EvolutionVersionRendering: Sendable {
    /// The version's indexing/printing event dispatcher, for reporting header
    /// print failures (same contract as `SwiftDiffableInterfaceRenderer`).
    var eventDispatcher: SwiftIndexEvents.Dispatcher { get }

    /// Index the binary and force full member indexing
    /// (`SwiftDiffableInterfaceBuilder.prepare()`).
    func prepare() async throws

    /// Freeze the prepared model into the `ABISnapshot` currency
    /// `ABIEvolutionBuilder` consumes.
    func snapshot() -> ABISnapshot

    // MARK: Model access (plain declaration-model values, reader-free)

    var rootTypeDefinitions: [TypeDefinition] { get }
    var rootProtocolDefinitions: [ProtocolDefinition] { get }
    var typeExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> { get }
    var protocolExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> { get }
    var typeAliasExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> { get }
    var conformanceExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> { get }
    var globalVariableDefinitions: [VariableDefinition] { get }
    var globalFunctionDefinitions: [FunctionDefinition] { get }

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

/// The one concrete `EvolutionVersionRendering`: a per-version
/// `SwiftDiffableInterfaceBuilder` plus a printer sharing that builder's event
/// dispatcher — the same dispatcher-sharing contract as
/// `SwiftDiffableInterfaceRenderer`, so the handlers the host passed to the
/// evolution builder cover printing too.
final class EvolutionVersionUnit<MachO: FieldLayoutRenderable>: EvolutionVersionRendering {
    private let builder: SwiftDiffableInterfaceBuilder<MachO>
    private let printer: SwiftDeclarationPrinter<MachO>

    init(
        configuration: SwiftDeclarationIndexConfiguration,
        eventHandlers: [SwiftIndexEvents.Handler],
        machO: MachO
    ) {
        let builder = SwiftDiffableInterfaceBuilder(configuration: configuration, eventHandlers: eventHandlers, in: machO)
        self.builder = builder
        self.printer = .init(eventDispatcher: builder.indexer.eventDispatcher, in: machO)
    }

    var eventDispatcher: SwiftIndexEvents.Dispatcher { builder.indexer.eventDispatcher }

    func prepare() async throws {
        try await builder.prepare()
    }

    func snapshot() -> ABISnapshot {
        builder.snapshot()
    }

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
