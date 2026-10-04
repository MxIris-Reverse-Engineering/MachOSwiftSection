import Foundation
import MachOKit
import ObjCDeclarationRendering
import ObjCOutputTransformer
import OutputTransformer
import Semantic

/// `swift-section objc dump`: print every Objective-C declaration in a binary.
public struct ObjCDumpRequest: Sendable, Equatable {
    public var source: MachOSource
    /// The kinds to print, in this order; `nil` prints all of them. Only kinds
    /// named here are reported when empty — otherwise every dump of a
    /// pure-Swift binary would note the kinds nobody asked for.
    public var kinds: [ObjCDeclarationKind]?
    /// Only declarations whose name contains this text, case-insensitively.
    public var nameFilter: String?
    public var generation: ObjCGenerationOptions
    /// Other spellings for C primitive types (`double` → `CGFloat`).
    public var cTypeReplacements: [ObjCPrimitiveTypePattern: String]
    /// A custom ivar-offset comment. Giving one turns ivar offset comments on.
    public var ivarOffsetComment: Transformer.ObjCIvarOffset?
    /// Whether indexing progress is reported as diagnostics.
    public var reportsIndexingProgress: Bool
    /// How the diagnostics name the image; `nil` derives it from `source`.
    public var imageDescription: String?
    public var destination: ProductDestination

    public init(
        source: MachOSource,
        kinds: [ObjCDeclarationKind]? = nil,
        nameFilter: String? = nil,
        generation: ObjCGenerationOptions = .init(),
        cTypeReplacements: [ObjCPrimitiveTypePattern: String] = [:],
        ivarOffsetComment: Transformer.ObjCIvarOffset? = nil,
        reportsIndexingProgress: Bool = false,
        imageDescription: String? = nil,
        destination: ProductDestination = .output
    ) {
        self.source = source
        self.kinds = kinds
        self.nameFilter = nameFilter
        self.generation = generation
        self.cTypeReplacements = cTypeReplacements
        self.ivarOffsetComment = ivarOffsetComment
        self.reportsIndexingProgress = reportsIndexingProgress
        self.imageDescription = imageDescription
        self.destination = destination
    }

    /// Prints the declarations, then notes why the dump came out empty, if it
    /// did.
    @discardableResult
    public func run(output: some SwiftSectionOutput) async throws -> Outcome {
        let session = try await ObjCInterfaceSession.make(
            source: source,
            generation: generation,
            cTypeReplacements: cTypeReplacements,
            ivarOffsetComment: ivarOffsetComment,
            reportsIndexingProgress: reportsIndexingProgress,
            output: output
        )

        var nameCountByKind: [ObjCDeclarationKind: Int] = [:]
        var emittedCount = 0
        var dumpedText = ""

        for kind in kinds ?? ObjCDeclarationKind.allCases {
            let names = session.names(of: kind)
            nameCountByKind[kind] = names.count
            for name in names where matchesFilter(name) {
                guard let interface = session.interface(of: kind, named: name) else { continue }
                switch destination {
                case .output:
                    output.write(.declarations(interface), declaring: .objc(kind, name: name))
                    output.write(.text(""))
                case .file:
                    dumpedText.append(interface.string)
                    dumpedText.append("\n\n")
                }
                emittedCount += 1
            }
        }

        if case .file(let path) = destination {
            try dumpedText.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        }

        // `session.isEmpty` walks every kind, so it is only consulted once the
        // requested ones have already come back empty.
        let isEntireIndexEmpty = nameCountByKind.values.allSatisfy { $0 == 0 } && session.isEmpty
        let outcome = Outcome(
            imageDescription: imageDescription ?? source.imageDescription,
            explicitKinds: kinds,
            nameCountByKind: nameCountByKind,
            isEntireIndexEmpty: isEntireIndexEmpty,
            filter: nameFilter,
            emittedCount: emittedCount
        )
        for note in Self.diagnosticNotes(for: outcome) {
            output.reportNote(note)
        }
        return outcome
    }

    /// What one dump actually found, as far as its diagnostics care.
    public struct Outcome: Sendable, Equatable {
        public var imageDescription: String
        /// The kinds the request named, or `nil` when every kind was dumped by
        /// default.
        public var explicitKinds: [ObjCDeclarationKind]?
        public var nameCountByKind: [ObjCDeclarationKind: Int]
        public var isEntireIndexEmpty: Bool
        public var filter: String?
        public var emittedCount: Int

        public init(
            imageDescription: String,
            explicitKinds: [ObjCDeclarationKind]?,
            nameCountByKind: [ObjCDeclarationKind: Int],
            isEntireIndexEmpty: Bool,
            filter: String?,
            emittedCount: Int
        ) {
            self.imageDescription = imageDescription
            self.explicitKinds = explicitKinds
            self.nameCountByKind = nameCountByKind
            self.isEntireIndexEmpty = isEntireIndexEmpty
            self.filter = filter
            self.emittedCount = emittedCount
        }
    }

    /// Why a dump produced nothing, in the caller's terms.
    ///
    /// Without these, three unrelated situations look the same — no product,
    /// no diagnostic — and a binary that carries no Objective-C cannot be told
    /// from one whose metadata failed to read. Pure, so that the wording can
    /// be tested without running a dump.
    public static func diagnosticNotes(for outcome: Outcome) -> [String] {
        // Subsumes the per-kind notes: reporting each requested kind as empty
        // would just be five ways of saying the same thing.
        if outcome.isEntireIndexEmpty {
            return ["no Objective-C metadata found in \(outcome.imageDescription)"]
        }

        var notes: [String] = []
        for kind in outcome.explicitKinds ?? [] where outcome.nameCountByKind[kind, default: 0] == 0 {
            notes.append("no \(kind.rawValue) found in \(outcome.imageDescription)")
        }

        let totalNameCount = outcome.nameCountByKind.values.reduce(0, +)
        if let filter = outcome.filter, !filter.isEmpty, outcome.emittedCount == 0, totalNameCount > 0 {
            let declarationNoun = totalNameCount == 1 ? "declaration" : "declarations"
            notes.append("--filter '\(filter)' matched none of the \(totalNameCount) \(declarationNoun) in \(outcome.imageDescription)")
        }
        return notes
    }

    private func matchesFilter(_ name: String) -> Bool {
        guard let nameFilter, !nameFilter.isEmpty else { return true }
        return name.range(of: nameFilter, options: .caseInsensitive) != nil
    }
}
