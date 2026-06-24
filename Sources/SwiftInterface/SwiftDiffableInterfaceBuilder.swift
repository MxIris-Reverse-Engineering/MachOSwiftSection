import SwiftDeclaration
@_spi(Support) import SwiftIndexing
import SwiftDeclarationRendering
import SwiftDiffing
import MachOSwiftSection

/// The ABI-diff analogue of ``SwiftInterfaceBuilder``.
///
/// Where `SwiftInterfaceBuilder` indexes one binary and *prints* it,
/// `SwiftDiffableInterfaceBuilder` indexes one binary and *freezes* it into the
/// `ABIModule` / `ABISnapshot` currency that `ABIDiffer` compares. Build one per
/// binary, `prepare()` each, then hand their `abiModule()`s (or `snapshot()`s)
/// to `ABIDiffer`.
///
/// Unlike the printer-driven flow, the differ never prints, so `prepare()` must
/// force the otherwise-lazy per-definition member indexing itself — see below.
public final class SwiftDiffableInterfaceBuilder<MachO: FieldLayoutRenderable>: Sendable {
    public let machO: MachO

    @_spi(Support)
    public let indexer: SwiftDeclarationIndexer<MachO>

    public init(
        configuration: SwiftDeclarationIndexConfiguration = .init(),
        eventHandlers: [SwiftIndexEvents.Handler] = [],
        in machO: MachO
    ) {
        self.machO = machO
        self.indexer = .init(configuration: configuration, eventHandlers: eventHandlers, in: machO)
    }

    /// Index the binary **and** fully index every definition's members so the
    /// resulting `ABIModule` is complete.
    ///
    /// `indexer.prepare()` only populates the coarse buckets; each definition's
    /// members stay empty until `index(in:)` is called on it — normally driven
    /// lazily by the printer. The differ never prints, so we drive that pass
    /// here. (`index(in:)` is `package`-scoped and idempotent, so this is safe
    /// and cheap to re-enter; it is callable because this builder lives in the
    /// same package as the model.)
    public func prepare() async throws {
        try await indexer.prepare()

        for typeDefinition in indexer.allTypeDefinitions.values {
            try await typeDefinition.index(in: machO)
        }
        for protocolDefinition in indexer.allProtocolDefinitions.values {
            try await protocolDefinition.index(in: machO)
        }
        for bucket in [
            indexer.typeExtensionDefinitions,
            indexer.protocolExtensionDefinitions,
            indexer.typeAliasExtensionDefinitions,
            indexer.conformanceExtensionDefinitions,
        ] {
            for extensionDefinitions in bucket.values {
                for extensionDefinition in extensionDefinitions {
                    try await extensionDefinition.index(in: machO)
                }
            }
        }
        // Globals are fully built by `indexer.prepare()`; no per-definition pass.
    }

    /// The frozen-input snapshot. Every field is a 1:1 passthrough of an indexer
    /// property, so this is a pure projection (call after `prepare()`).
    public func abiModule() -> ABIModule {
        ABIModule(
            rootTypeDefinitions: indexer.rootTypeDefinitions,
            allTypeDefinitions: indexer.allTypeDefinitions,
            rootProtocolDefinitions: indexer.rootProtocolDefinitions,
            allProtocolDefinitions: indexer.allProtocolDefinitions,
            typeExtensionDefinitions: indexer.typeExtensionDefinitions,
            protocolExtensionDefinitions: indexer.protocolExtensionDefinitions,
            typeAliasExtensionDefinitions: indexer.typeAliasExtensionDefinitions,
            conformanceExtensionDefinitions: indexer.conformanceExtensionDefinitions,
            globalVariableDefinitions: indexer.globalVariableDefinitions,
            globalFunctionDefinitions: indexer.globalFunctionDefinitions
        )
    }

    /// Convenience: freeze straight to the `Codable` snapshot for persistence
    /// (store it as a baseline and diff against it later without the binary).
    public func snapshot() -> ABISnapshot {
        ABIDiffer().snapshot(of: abiModule())
    }
}
