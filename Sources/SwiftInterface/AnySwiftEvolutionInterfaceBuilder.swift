import Foundation
import SwiftDeclaration
@_spi(Support) import SwiftIndexing
import SwiftDeclarationRendering
import SwiftDiffing
import MachOSwiftSection
import Semantic
import SwiftStdlibToolbox

/// Renders one module's ABI across N ≥ 2 ordered binary versions as a single
/// **union interface with lifecycle annotations** — the N-way, human-readable
/// counterpart of `swift-section evolution`'s lineage report, and the
/// evolution analogue of the `SwiftDiffableInterfaceBuilder` +
/// `SwiftDiffableInterfaceRenderer` pair.
///
/// Every declaration that ever existed on the axis renders exactly once, from
/// the last version that has it; declarations that changed carry a trailing
/// `// [●●○] removed in 26.0`-style annotation (presence bitmap + event
/// phrases, legend in the file header), and declarations present throughout
/// with no changes carry none. Annotation facts come from `ABIEvolutionBuilder`
/// over the same frozen snapshots the lineage report uses, so the two views
/// cannot disagree.
///
/// Usage: construct with N binaries (oldest first) and their axis labels,
/// `try await prepare()`, then `printAnnotatedInterface()`. All inputs must be
/// live binaries — a persisted snapshot carries no renderable interface.
///
/// This is the **type-erased** builder: each version's reader type is erased
/// at construction, so the version count is a runtime value — the form the
/// CLI and any host letting the user pick an arbitrary set of versions need
/// (a parameter pack's arity is fixed at compile time and cannot express
/// runtime-N). When the version list IS known at compile time, prefer the
/// pack-generic ``SwiftEvolutionInterfaceBuilder``, which carries the reader
/// types in its signature and delegates here.
public final class AnySwiftEvolutionInterfaceBuilder: Sendable {
    /// Oldest → newest, index-aligned with `labels`.
    private let versionUnits: [any InterfaceVersionRendering]

    /// The version-axis labels, oldest first (e.g. `["17.0", "18.0", "26.0"]`).
    public let labels: [String]

    /// The `@available` platform spelling (`"iOS"`, `"macOS"`, …) for genuine
    /// availability attributes above declarations whose lifecycle is fully
    /// expressible as one attribute (evolution proposal
    /// draft-evolution-interface-available-annotations); `nil` — the default —
    /// disables them and keeps output byte-identical to the pre-attribute
    /// builder. Inexpressible lifecycles (disappeared-and-returned shapes,
    /// non-version labels, modified-only histories) never emit an attribute;
    /// the bitmap comment stays the carrier of the full truth either way.
    public let availabilityAnnotationPlatform: String?

    @Mutex
    private var preparedEvolution: ABIEvolution? = nil

    /// Homogeneous construction: N versions of the same reader type, count
    /// decided at runtime.
    ///
    /// - Throws: `ABIEvolutionError.fewerThanTwoVersions` /
    ///   `.labelCountMismatch` on invalid input shapes.
    public init<MachO: FieldLayoutRenderable>(
        configuration: SwiftDeclarationIndexConfiguration = .init(),
        eventHandlers: [SwiftIndexEvents.Handler] = [],
        versions: [MachO],
        labels: [String],
        availabilityAnnotationPlatform: String? = nil
    ) throws {
        try Self.validate(versionCount: versions.count, labelCount: labels.count)
        self.versionUnits = versions.map {
            InterfaceVersionUnit(configuration: configuration, eventHandlers: eventHandlers, machO: $0)
        }
        self.labels = labels
        self.availabilityAnnotationPlatform = availabilityAnnotationPlatform
    }

    /// Heterogeneous construction: each version brings its own reader type.
    /// Packs in *function* position need no runtime-availability gate (unlike
    /// packs in a type's generic parameter list), so this initializer is
    /// available everywhere the package deploys.
    public init<each Reader: FieldLayoutRenderable>(
        configuration: SwiftDeclarationIndexConfiguration = .init(),
        eventHandlers: [SwiftIndexEvents.Handler] = [],
        versions: repeat each Reader,
        labels: [String],
        availabilityAnnotationPlatform: String? = nil
    ) throws {
        var units: [any InterfaceVersionRendering] = []
        for machO in repeat each versions {
            units.append(InterfaceVersionUnit(configuration: configuration, eventHandlers: eventHandlers, machO: machO))
        }
        try Self.validate(versionCount: units.count, labelCount: labels.count)
        self.versionUnits = units
        self.labels = labels
        self.availabilityAnnotationPlatform = availabilityAnnotationPlatform
    }

    private static func validate(versionCount: Int, labelCount: Int) throws {
        guard versionCount >= 2 else {
            throw ABIEvolutionError.fewerThanTwoVersions(versionCount: versionCount)
        }
        guard labelCount == versionCount else {
            throw ABIEvolutionError.labelCountMismatch(labelCount: labelCount, versionCount: versionCount)
        }
    }

    // MARK: - Preparation

    /// Indexes every version (full member indexing included), freezes each
    /// into a snapshot, and builds the `ABIEvolution` annotation matrix. Must
    /// complete before any rendering entry point.
    public func prepare() async throws {
        for versionUnit in versionUnits {
            try await versionUnit.prepare()
        }
        let snapshots = versionUnits.map { $0.snapshot() }
        let versionDescriptors = labels.map { ABIVersionDescriptor(label: $0) }
        preparedEvolution = try ABIEvolutionBuilder().evolution(of: snapshots, versions: versionDescriptors)
    }

    /// The evolution built by `prepare()` — the same value the lineage report
    /// and JSON paths consume, exposed so a host can reuse it directly (CI
    /// verdicts via `hasBreakingChange`, warnings display). `nil` until
    /// `prepare()` completes.
    public var evolution: ABIEvolution? { preparedEvolution }

    // MARK: - Rendering

    /// The full annotated union interface: legend header, every declaration
    /// block, and a warnings tail when the evolution carries diagnostics.
    ///
    /// - Throws: ``SwiftEvolutionInterfaceBuilderError/notPrepared`` when
    ///   called before `prepare()`.
    public func printAnnotatedInterface() async throws -> SemanticString {
        let evolution = try requirePrepared()
        let blocks = await makeRenderer(for: evolution).annotatedBlocks()
        return EvolutionMarking.renderInterface(
            blocks: blocks,
            evolution: evolution,
            availabilityAnnotationPlatform: availabilityAnnotationPlatform
        )
    }

    /// The structured line stream behind ``printAnnotatedInterface()``: the
    /// outer array is the top-level declaration blocks in render order, each
    /// inner array one block's lines with their lifecycle annotations still
    /// data (not text). For hosts that render the evolution themselves
    /// (custom coloring, folding) — the evolution analogue of the two-sided
    /// renderer's `annotatedDiffBlocks()`.
    @_spi(Support)
    public func annotatedBlocks() async throws -> [[EvolutionLine]] {
        try await makeRenderer(for: requirePrepared()).annotatedBlocks()
    }

    private func makeRenderer(for evolution: ABIEvolution) -> SwiftEvolutionInterfaceRenderer {
        SwiftEvolutionInterfaceRenderer(
            versions: versionUnits,
            annotations: EvolutionAnnotationIndex(evolution: evolution),
            versionDescriptors: evolution.versions,
            availabilityAnnotationPlatform: availabilityAnnotationPlatform
        )
    }

    private func requirePrepared() throws -> ABIEvolution {
        guard let evolution = preparedEvolution else {
            throw SwiftEvolutionInterfaceBuilderError.notPrepared
        }
        return evolution
    }
}

/// Usage-contract failures of the evolution interface builders. (Input-shape
/// failures throw `ABIEvolutionError` from the initializers instead, shared
/// with `ABIEvolutionBuilder`.)
public enum SwiftEvolutionInterfaceBuilderError: Swift.Error, Equatable, CustomStringConvertible {
    /// A rendering entry point ran before `prepare()` completed.
    case notPrepared

    public var description: String {
        switch self {
        case .notPrepared:
            return "SwiftEvolutionInterfaceBuilder needs prepare() to complete before rendering."
        }
    }
}
