@_spi(Support) @testable import SwiftPrinting
import Foundation
import Demangling
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
@_spi(Internals) import SwiftInspection

// MARK: - Shared survey

/// One node kind `SwiftPrinting` renders as the empty string while the upstream
/// `Demangling` `NodePrinter` renders as something.
struct NodeKindParityGap {
    var occurrences = 0
    var upstreamSample = ""
    var enclosingSample = ""
}

/// Surveys real type trees for the silent-empty-render failure both the test
/// and the probe below are built on.
///
/// The failure is silent by construction: `dispatchPrintName` asks the five
/// `printNameIn*` in turn and, when all decline, writes nothing at all. A kind
/// with no `case` therefore prints as `""`, which surfaces downstream as
/// `Predicate<>`, a bare `-> `, or `var x: ` — syntactically broken Swift that
/// the dump path (on the upstream printer) renders correctly, so the two paths
/// silently disagree and only the interface is wrong.
enum NodeKindParitySurvey {
    /// How many Swift symbols to mine for type subtrees. SwiftUI has hundreds
    /// of thousands; the gap kinds repeat long before the budget runs out.
    static let symbolBudget = 40000

    /// Renderings that can only come from a child printing as the empty string.
    static func carriesEmptyStringFingerprint(_ text: String) -> Bool {
        text.contains("<>")
            || text.contains("<, ")
            || text.contains(", >")
            || text.hasSuffix("-> ")
            || text.hasSuffix(": ")
    }

    static func ourRendering(of node: Node) async -> String {
        var printer = TypeNodePrinter()
        return ((try? await printer.printRoot(node))?.string) ?? ""
    }

    /// Whether every child renders non-empty, i.e. this node is the deepest
    /// point the emptiness originates at. A childless node trivially qualifies.
    private static func childrenAllRender(_ node: Node) async -> Bool {
        for child in node.children {
            let upstreamText = await child.print(using: .default)
            guard !upstreamText.isEmpty else { continue }
            if await ourRendering(of: child).isEmpty { return false }
        }
        return true
    }

    struct Result {
        var gapsByKind: [Node.Kind: NodeKindParityGap] = [:]
        var suspectTreeCount = 0
        /// Trees whose rendering carries a fingerprint that could not be
        /// pinned on any node — the survey's own blind spot, kept visible
        /// rather than dropped. A bracket printed where none belongs (an empty
        /// generic parameter list) lands here, because nothing rendered empty.
        var unattributedSamples: [String] = []
    }

    static func run(on machOFile: MachOFile) async throws -> Result {
        var result = Result()

        for tree in try typeTrees(in: machOFile) {
            let ourText = await ourRendering(of: tree)
            guard carriesEmptyStringFingerprint(ourText) else { continue }
            result.suspectTreeCount += 1

            var attributed = false
            // `Node` iterates preorder INCLUDING itself — the whole subtree is
            // exactly what we want here.
            for node in tree {
                let upstreamText = await node.print(using: .default)
                guard !upstreamText.isEmpty else { continue }
                guard await ourRendering(of: node).isEmpty else { continue }
                // Report only the DEEPEST empty node. A parent prints empty
                // whenever a child does, so without this every gap also
                // indicts its whole ancestor chain (`.type`, `.typeList`,
                // `.boundGenericStructure` …) — kinds we do handle.
                guard await childrenAllRender(node) else { continue }
                attributed = true
                var gap = result.gapsByKind[node.kind] ?? NodeKindParityGap()
                gap.occurrences += 1
                if gap.upstreamSample.isEmpty {
                    gap.upstreamSample = upstreamText
                    gap.enclosingSample = ourText
                }
                result.gapsByKind[node.kind] = gap
            }

            if !attributed, result.unattributedSamples.count < 20 {
                result.unattributedSamples.append(ourText)
            }
        }

        return result
    }

    /// Three sources. Field records and associated-type witnesses carry a type
    /// tree directly; symbols carry method signatures, and it is inside THOSE
    /// that a return or parameter type lives — the `-> ` (empty return type)
    /// symptom has no other source, which is why a survey over the first two
    /// alone reports a clean bill for `.constrainedExistential`.
    static func typeTrees(in machOFile: MachOFile) throws -> [Node] {
        var trees: [Node] = []

        for wrapper in try machOFile.swift.typeContextDescriptors {
            let descriptor = wrapper.typeContextDescriptor
            guard let fieldDescriptor = try? descriptor.fieldDescriptor(in: machOFile) else { continue }
            for record in try fieldDescriptor.records(in: machOFile) {
                guard let mangledTypeName = try? record.mangledTypeName(in: machOFile),
                      let typeNode = try? SymbolicDemangler.demangleType(for: mangledTypeName, in: machOFile)
                else { continue }
                trees.append(typeNode)
            }
        }

        for associatedType in try machOFile.swift.associatedTypes {
            for record in associatedType.records {
                guard let substituted = try? record.substitutedTypeName(in: machOFile),
                      let typeNode = try? SymbolicDemangler.demangleType(for: substituted, in: machOFile)
                else { continue }
                trees.append(typeNode)
            }
        }

        var symbolsMined = 0
        for symbol in machOFile.symbols where symbol.name.isSwiftSymbol {
            guard symbolsMined < symbolBudget else { break }
            symbolsMined += 1
            guard let signature = try? demangleAsNodeTransient(symbol.name) else { continue }
            // Only the type subtrees are what the type printer ever sees; the
            // entity scaffolding around them belongs to the function printer.
            for node in signature where node.kind == .type {
                trees.append(node)
            }
        }

        return trees
    }
}

// MARK: - The standing test

/// Fails when a node kind reaching a type position renders as the empty string.
///
/// This is the asset the parity batch exists to leave behind. Every gap it now
/// guards was found by hand in a 106903-line interface dump, by eye, twice —
/// `Pack` (718 occurrences in SwiftUI, printing `Predicate<>`),
/// `ConstrainedExistential*` (an entire return type vanishing into `-> `),
/// `Index` and `OpaqueTypeDescriptorSymbolicReference`. A behavioural
/// comparison rather than a `case`-list diff, so it does not rot when upstream
/// adds or removes kinds.
@Suite(.serialized)
struct NodeKindParityTests {
    /// Kinds that legitimately render empty from a TYPE printer, with the
    /// reason each is not a type position. Anything NOT on this list that
    /// renders empty is a bug — that is the whole assertion.
    ///
    /// Shrink-only by intent: adding an entry means claiming a kind never
    /// needs to print inside a type, so it needs a reason that survives
    /// reading.
    static let nonTypePositionKinds: [Node.Kind: String] = [
        .function: "entity scaffolding; FunctionNodePrinter owns it",
        .variable: "entity scaffolding; VariableNodePrinter owns it",
        .extension: "entity scaffolding; the extension header path owns it",
        .argumentTuple: "function-signature structure, printed by FunctionNodePrinter",
        .tupleElementName: "consumed inline by printTuple, never dispatched on its own",
        .firstElementMarker: "function-signature specialization metadata, not a type",
        .number: "function-signature specialization metadata, not a type",
    ]

    @Test func noTypePositionKindRendersEmpty() async throws {
        let cache = try DyldCache(path: .current)
        let machOFile = try #require(cache.machOFile(named: .SwiftUI), "the running system's cache has no SwiftUI")

        let result = try await NodeKindParitySurvey.run(on: machOFile)
        let unexpected = result.gapsByKind.filter { Self.nonTypePositionKinds[$0.key] == nil }

        #expect(
            unexpected.isEmpty,
            """
            These node kinds render as the empty string from SwiftPrinting while the upstream \
            NodePrinter renders them as something, which produces syntactically broken Swift \
            (`Foo<>`, a bare `-> `, `var x: `). Either add a `case` for the kind, or — if it \
            genuinely never occupies a type position — add it to `nonTypePositionKinds` with a \
            reason: \
            \(unexpected.map { "\($0.key) ×\($0.value.occurrences) (upstream: \($0.value.upstreamSample))" }.sorted().joined(separator: "; "))
            """
        )
    }
}

// MARK: - The probe

/// The same survey, printed in full instead of asserted — for when the standing
/// test goes red and the question becomes "what does this kind look like".
@Suite(.disabled("Research probe — enable explicitly when auditing printer parity"))
struct NodeKindParityProbe {
    @Test func reportsEveryKindAndSample() async throws {
        let cache = try DyldCache(path: .current)
        let machOFile = try #require(cache.machOFile(named: .SwiftUI), "the running system's cache has no SwiftUI")

        let result = try await NodeKindParitySurvey.run(on: machOFile)

        print("=== node kind parity probe: SwiftUI ===")
        print("trees carrying an empty-string fingerprint: \(result.suspectTreeCount)")
        print("")
        for (kind, gap) in result.gapsByKind.sorted(by: { $0.value.occurrences > $1.value.occurrences }) {
            let verdict = NodeKindParityTests.nonTypePositionKinds[kind].map { "allowed — \($0)" } ?? "GAP"
            print("\(kind)  ×\(gap.occurrences)  [\(verdict)]")
            print("    upstream prints: \(gap.upstreamSample)")
            print("    we print:        \(gap.enclosingSample)")
        }
        if !result.unattributedSamples.isEmpty {
            print("")
            print("--- fingerprint present but no node attributed (survey blind spot) ---")
            for sample in result.unattributedSamples { print("    \(sample)") }
        }
    }
}
