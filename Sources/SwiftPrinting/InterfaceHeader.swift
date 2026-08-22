import Foundation
import MachOKit
import MachOKitExtensions
@_spi(Internals) import MachOSymbols
import Demangling
import Dependencies
import Semantic

// MARK: - Interface Header Info

/// Pure-value input for `InterfaceHeaderBlock` (evolution proposal 0008).
///
/// Built either directly (RuntimeViewer supplies its own generator identity
/// and any fields it already knows) or through the
/// `init(machO:generatorName:generatorVersion:...)` factory, which reads the
/// Mach-O facts (install name, UUID, architecture, file type, dispatch-thunk
/// count) from the binary.
///
/// `generatedDate` is deliberately optional and defaults to absent: a date
/// line breaks the byte-stability of snapshots and baselines, so tests and
/// the default CLI output never carry one.
public struct InterfaceHeaderInfo: Equatable, Sendable {
    /// The tool that produced the output (e.g. `"swift-section"`).
    public var generatorName: String

    /// The producing tool's version string (e.g. `"0.16.0"`).
    public var generatorVersion: String

    /// The image's install name (`LC_ID_DYLIB`) or load path; the line is
    /// omitted when absent.
    public var imagePath: String?

    /// The image's `LC_UUID`; the line is omitted when absent.
    public var uuid: UUID?

    /// Human-readable architecture (e.g. `"arm64e"`); omitted when absent.
    public var cpuDescription: String?

    /// Human-readable Mach-O file type (e.g. `"dylib"`); omitted when absent.
    public var fileTypeDescription: String?

    /// When set, a `Generated at:` line with the ISO-8601 date. `nil` (the
    /// default everywhere) keeps the output byte-stable.
    public var generatedDate: Date?

    /// The image's dispatch-thunk (`Tj`) symbol count, the one signal that
    /// separates a library-evolution build from a non-resilient one (issue
    /// #106 measured it as the only discriminating count — `Tq` and `MV`
    /// both appear in evolution-off builds). `nil` omits the line.
    ///
    /// The rendered wording is "detected / not detected", never an
    /// assertion: a resilient module with no dispatchable public member can
    /// legitimately count zero.
    public var dispatchThunkCount: Int?

    /// Whether to append the short "not recoverable from the binary" block
    /// (issue #106 §8): facts source code carried but the binary provably
    /// does not, so their absence reads as "omitted", not "never written".
    public var includesUnrecoverableNotes: Bool

    public init(
        generatorName: String,
        generatorVersion: String,
        imagePath: String? = nil,
        uuid: UUID? = nil,
        cpuDescription: String? = nil,
        fileTypeDescription: String? = nil,
        generatedDate: Date? = nil,
        dispatchThunkCount: Int? = nil,
        includesUnrecoverableNotes: Bool = true
    ) {
        self.generatorName = generatorName
        self.generatorVersion = generatorVersion
        self.imagePath = imagePath
        self.uuid = uuid
        self.cpuDescription = cpuDescription
        self.fileTypeDescription = fileTypeDescription
        self.generatedDate = generatedDate
        self.dispatchThunkCount = dispatchThunkCount
        self.includesUnrecoverableNotes = includesUnrecoverableNotes
    }
}

extension InterfaceHeaderInfo {
    /// Reads the Mach-O facts from `machO`: install name / path, `LC_UUID`,
    /// architecture, file type, and the dispatch-thunk count from the
    /// image's symbol index.
    public init<MachO: MachORepresentableWithCache>(
        machO: MachO,
        generatorName: String,
        generatorVersion: String,
        generatedDate: Date? = nil,
        includesUnrecoverableNotes: Bool = true
    ) {
        @Dependency(\.symbolIndexStore)
        var symbolIndexStore

        let imagePath: String? = switch machO {
        case let machOFile as MachOFile: machOFile.imagePath
        case let machOImage as MachOImage: machOImage.path
        default: nil
        }

        var uuid: UUID?
        for loadCommand in machO.loadCommands {
            if case .uuid(let uuidCommand) = loadCommand {
                uuid = uuidCommand.uuid
                break
            }
        }

        self.init(
            generatorName: generatorName,
            generatorVersion: generatorVersion,
            imagePath: imagePath,
            uuid: uuid,
            cpuDescription: Self.conciseCPUDescription(machO.header.cpu),
            fileTypeDescription: Self.conciseFileTypeDescription(machO.header.fileType),
            generatedDate: generatedDate,
            dispatchThunkCount: symbolIndexStore.symbols(of: Node.Kind.dispatchThunk, in: machO).count,
            includesUnrecoverableNotes: includesUnrecoverableNotes
        )
    }

    /// The short architecture name a reader expects (`arm64e`), falling back
    /// to MachOKit's `type(subtype)` rendering for anything uncommon.
    private static func conciseCPUDescription(_ cpu: CPU) -> String {
        switch (cpu.type, cpu.subtype) {
        case (.x86_64, .x86(.x86_all)), (.x86_64, .x86(.x86_64_all)):
            return "x86_64"
        case (.arm64, .arm64(.arm64_all)):
            return "arm64"
        case (.arm64, .arm64(.arm64e)):
            return "arm64e"
        default:
            return cpu.description
        }
    }

    /// `MH_DYLIB` → `dylib`; MachOKit's constant-name rendering kept only
    /// when the `MH_` prefix is unexpectedly absent.
    private static func conciseFileTypeDescription(_ fileType: FileType?) -> String? {
        guard let fileType else { return nil }
        let constantName = fileType.description
        guard constantName.hasPrefix("MH_") else { return constantName }
        return String(constantName.dropFirst(3)).lowercased()
    }
}

// MARK: - Interface Header Block

/// Renders `InterfaceHeaderInfo` as the leading comment block of a
/// generated interface / dump (evolution proposal 0008):
///
/// ```
/// // Generated by swift-section 0.16.0
/// // Image: /path/to/SourceEditor (arm64e, dylib)
/// // UUID: 269D2B6E-DB35-3B93-97E0-B1B71D0DB64E
/// // Library evolution: detected (2216 dispatch thunks)
/// // Not recoverable from the binary (omitted, not absent):
/// //   ...
/// ```
///
/// Public deliberately: RuntimeViewer's per-type export bypasses
/// `printRoot`, so the header must be callable as a standalone component.
public struct InterfaceHeaderBlock: SemanticStringComponent {
    public let info: InterfaceHeaderInfo

    public init(_ info: InterfaceHeaderInfo) {
        self.info = info
    }

    /// The short unrecoverable-facts list. The full catalog with root
    /// causes lives in the repository's roadmap ("Known limitations");
    /// this is the reader-facing digest.
    static let unrecoverableNoteLines: [String] = [
        "Not recoverable from the binary (omitted, not absent):",
        "  `T!` prints as `T?` (ABI-identical) · parameter internal names · @available ·",
        "  @discardableResult · default argument values · internal vs fileprivate ·",
        "  @frozen · class-level @MainActor · open vs public",
    ]

    public func buildComponents() -> [AtomicComponent] {
        var lines: [String] = []

        lines.append("Generated by \(info.generatorName) \(info.generatorVersion)")

        if let imagePath = info.imagePath {
            let annotations = [info.cpuDescription, info.fileTypeDescription].compactMap { $0 }
            if annotations.isEmpty {
                lines.append("Image: \(imagePath)")
            } else {
                lines.append("Image: \(imagePath) (\(annotations.joined(separator: ", ")))")
            }
        }

        if let uuid = info.uuid {
            lines.append("UUID: \(uuid.uuidString)")
        }

        if let generatedDate = info.generatedDate {
            lines.append("Generated at: \(ISO8601DateFormatter().string(from: generatedDate))")
        }

        if let dispatchThunkCount = info.dispatchThunkCount {
            if dispatchThunkCount > 0 {
                lines.append("Library evolution: detected (\(dispatchThunkCount) dispatch thunks)")
            } else {
                lines.append("Library evolution: not detected (0 dispatch thunks)")
            }
        }

        if info.includesUnrecoverableNotes {
            lines.append(contentsOf: Self.unrecoverableNoteLines)
        }

        var result: [AtomicComponent] = []
        for line in lines {
            result.append(contentsOf: Comment(line).buildComponents())
            result.append(contentsOf: BreakLine().buildComponents())
        }
        // Trailing blank line so the header reads apart from whatever
        // follows (the imports block in `printRoot`, a type in a per-type
        // export).
        result.append(contentsOf: BreakLine().buildComponents())
        return result
    }
}
