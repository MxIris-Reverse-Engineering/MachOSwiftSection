import ArgumentParser
import Foundation
import MachOKit
import Semantic

struct ObjCDumpCommand: AsyncParsableCommand, Sendable {
    static let configuration: CommandConfiguration = .init(
        commandName: "dump",
        abstract: "Dump every Objective-C declaration in a Mach-O file or dyld shared cache image."
    )

    @OptionGroup
    var machOOptions: ObjCMachOOptionGroup

    @OptionGroup(title: "Generation")
    var generationOptions: ObjCGenerationOptionGroup

    @OptionGroup(title: "Comment Templates")
    var transformerOptions: ObjCTransformerOptionGroup

    @Option(
        name: .shortAndLong,
        help: ArgumentHelp(
            "The kinds of declaration to dump, comma-separated (e.g. classes,protocols). If not specified, all of them are dumped.",
            valueName: "kinds"
        )
    )
    var sections: ObjCSectionKindList?

    @Option(name: .shortAndLong, help: "Only dump declarations whose name contains this text, case-insensitively.")
    var filter: String?

    @Option(name: .shortAndLong, help: "The output path for the dump. If not specified, the output is printed to stdout.", completion: .file())
    var outputPath: String?

    @Option(name: .shortAndLong, help: "The color scheme for the output.")
    var colorScheme: SemanticColorScheme = .none

    @Flag(name: .shortAndLong, help: "Report indexing progress on stderr.")
    var verbose: Bool = false

    func run() async throws {
        let session = try await ObjCInterfaceSession.make(
            machOOptions: machOOptions,
            generationOptions: generationOptions,
            transformerOptions: transformerOptions,
            isVerbose: verbose
        )

        let requestedKinds = sections?.kinds
        let kinds = requestedKinds ?? ObjCSectionKind.allCases
        var nameCountByKind: [ObjCSectionKind: Int] = [:]
        var emittedCount = 0
        var dumpedString = ""

        for kind in kinds {
            let names = session.names(of: kind)
            nameCountByKind[kind] = names.count
            for name in names where matchesFilter(name) {
                guard let interface = session.interface(of: kind, named: name) else { continue }
                emit(interface, into: &dumpedString)
                emittedCount += 1
            }
        }

        if let outputPath {
            try dumpedString.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
        }

        // `session.isEmpty` walks every kind, so it is only consulted once the
        // requested ones have already come back empty.
        let isEntireIndexEmpty = nameCountByKind.values.allSatisfy { $0 == 0 } && session.isEmpty
        let outcome = Outcome(
            imageDescription: machOOptions.imageDescription,
            explicitKinds: requestedKinds,
            nameCountByKind: nameCountByKind,
            isEntireIndexEmpty: isEntireIndexEmpty,
            filter: filter,
            emittedCount: emittedCount
        )
        for note in Self.diagnosticNotes(for: outcome) {
            writeStandardErrorLine(note)
        }
    }

    /// Catches the spelling this option used to accept. `--sections classes protocols`
    /// leaves `protocols` sitting in the positional slot, so the binary would be
    /// looked for under a declaration kind's name — a confusing "no such file"
    /// far from the real mistake.
    ///
    /// Only the two-token shape is recoverable here: with a path as well
    /// (`--sections classes protocols /bin/ls`) the parser rejects the extra
    /// positional argument before `validate()` ever runs.
    func validate() throws {
        guard let sections,
              let filePath = machOOptions.filePath,
              ObjCSectionKind(rawValue: filePath) != nil
        else { return }

        let combinedKinds = (sections.kinds.map(\.rawValue) + [filePath]).joined(separator: ",")
        throw ValidationError(
            """
            '\(filePath)' was read as the input path, but it is also a declaration kind. \
            --sections takes one comma-separated value: write '--sections \(combinedKinds)' \
            and put the input path after it.
            """
        )
    }

    /// What one run actually found, as far as the diagnostics care.
    struct Outcome {
        var imageDescription: String
        /// The kinds the caller named with `--sections`, or `nil` when every
        /// kind was dumped by default. Only named kinds are reported as empty:
        /// otherwise every dump of a pure-Swift binary would nag about the four
        /// kinds the caller never asked for.
        var explicitKinds: [ObjCSectionKind]?
        var nameCountByKind: [ObjCSectionKind: Int]
        var isEntireIndexEmpty: Bool
        var filter: String?
        var emittedCount: Int
    }

    /// Why a dump produced nothing, in the caller's terms.
    ///
    /// Without these, three unrelated situations are byte-for-byte identical —
    /// empty stdout, empty stderr, exit code 0 — and there is no way to tell a
    /// binary that carries no Objective-C from one whose metadata failed to
    /// read. Pure so the wording can be tested without capturing a process's
    /// stderr; the exit code deliberately stays 0 in every case, so no existing
    /// script turns red over a diagnostic.
    static func diagnosticNotes(for outcome: Outcome) -> [String] {
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
        guard let filter, !filter.isEmpty else { return true }
        return name.range(of: filter, options: .caseInsensitive) != nil
    }

    private func emit(_ semanticString: SemanticString, into dumpedString: inout String) {
        if outputPath != nil {
            dumpedString.append(semanticString.string)
            dumpedString.append("\n\n")
        } else {
            semanticString.printColorfully(using: colorScheme)
            print("")
        }
    }
}
