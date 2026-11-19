import SwiftDeclaration
import SwiftDeclarationRendering
import Semantic

// MARK: - Offset Comment

/// An offset comment that outputs a comment when enabled — a `pwtOffset` or
/// a `fieldOffset` one, as `kind` says, when marking comment structure.
struct OffsetComment: SemanticStringComponent {
    let prefix: String

    let kind: AnnotationRegion.Kind

    let offset: Int?

    let emit: Bool

    let marksStructure: Bool

    init(prefix: String, kind: AnnotationRegion.Kind, offset: Int?, emit: Bool, marksStructure: Bool) {
        self.prefix = prefix
        self.kind = kind
        self.offset = offset
        self.emit = emit
        self.marksStructure = marksStructure
    }

    package func buildComponents() -> [AtomicComponent] {
        guard emit, let offset else { return [] }

        return StructuredComment.offset(labeled: prefix, offset).atoms(markingStructure: marksStructure, as: kind)
    }
}

// MARK: - Address Comment

/// An address comment that outputs a member address comment when enabled.
struct AddressComment: SemanticStringComponent {
    let addressString: String?

    let label: String?

    let emit: Bool

    let marksStructure: Bool

    init(addressString: String?, label: String? = nil, emit: Bool, marksStructure: Bool) {
        self.addressString = addressString
        self.label = label
        self.emit = emit
        self.marksStructure = marksStructure
    }

    package func buildComponents() -> [AtomicComponent] {
        guard emit, let addressString else { return [] }

        return StructuredComment.memberAddress(addressString: addressString, qualifier: label).atoms(markingStructure: marksStructure, as: .memberAddress)
    }
}

// MARK: - VTable Offset Comment

/// A vtable offset comment that outputs a vtable slot offset comment when enabled.
struct VTableOffsetComment: SemanticStringComponent {
    let vtableOffset: Int?

    let label: String?

    let emit: Bool

    let transformer: (@Sendable (Int, String?) -> SemanticString)?

    let marksStructure: Bool

    init(vtableOffset: Int?, label: String? = nil, emit: Bool, transformer: (@Sendable (Int, String?) -> SemanticString)?, marksStructure: Bool) {
        self.vtableOffset = vtableOffset
        self.label = label
        self.emit = emit
        self.transformer = transformer
        self.marksStructure = marksStructure
    }

    package func buildComponents() -> [AtomicComponent] {
        guard emit, let vtableOffset else { return [] }

        if let transformer {
            return StructuredComment.printedTemplate(transformer(vtableOffset, label), markingStructure: marksStructure, as: .vtableOffset).components
        } else {
            return StructuredComment.vtableOffset(vtableOffset, qualifier: label).atoms(markingStructure: marksStructure, as: .vtableOffset)
        }
    }
}

// MARK: - Export Status Comment

/// A `not exported` comment (evolution proposal 0008): emitted only when
/// the member's symbols provably have no export-trie entry. `isExported`
/// `nil` means "no verdict" — no export information in the image, or no
/// symbol evidence on the member — and emits nothing, so the annotation
/// never guesses. Unlike its sibling comment components this one carries
/// no `emit` flag: the caller gates on the configuration flag BEFORE
/// running the export query, so a constructed component is already past
/// the gate.
struct ExportStatusComment: SemanticStringComponent {
    let isExported: Bool?

    let marksStructure: Bool

    init(isExported: Bool?, marksStructure: Bool) {
        self.isExported = isExported
        self.marksStructure = marksStructure
    }

    package func buildComponents() -> [AtomicComponent] {
        guard isExported == false else { return [] }

        return StructuredComment.exportStatus.atoms(markingStructure: marksStructure, as: .exportStatus)
    }
}

// MARK: - Imports Block

/// A block of import statements.
package struct ImportsBlock: SemanticStringComponent {
    package let modules: [String]

    package init(_ modules: [String]) {
        self.modules = modules
    }

    package init(_ modules: String...) {
        self.modules = modules
    }

    package func buildComponents() -> [AtomicComponent] {
        guard !modules.isEmpty else { return [] }

        var result: [AtomicComponent] = []
        for module in modules {
            result.append(contentsOf: Standard("import \(module)").buildComponents())
            result.append(contentsOf: BreakLine().buildComponents())
        }
        return result
    }
}
