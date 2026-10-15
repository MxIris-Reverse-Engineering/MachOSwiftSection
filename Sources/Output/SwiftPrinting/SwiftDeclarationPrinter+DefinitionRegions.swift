import Demangling
import SwiftDeclaration
import Semantic

// MARK: - Marking Nested Definitions

/// What `SwiftDeclarationPrintConfiguration.marksNestedDefinitions` changes
/// in the printer (evolution proposal `nested-definition-regions`): the print
/// of each nested type or protocol is wrapped in a `DefinitionRegion` named
/// after it, so a host can take a nested definition out of its parent's print
/// instead of printing it a second time.
extension SwiftDeclarationPrinter {
    /// `printNested()` — a nested definition printed at its nesting level —
    /// wrapped in a region named after `name` when marking. A child the
    /// export filter removed prints nothing and gets no region.
    func nestedDefinition(named name: NodeReference, printing printNested: () async throws -> SemanticString) async rethrows -> SemanticString {
        let printed = try await printNested()
        guard configuration.marksNestedDefinitions, !printed.isEmpty, let identity = await definitionRegionIdentity(of: name) else {
            return printed
        }
        return SemanticString {
            DefinitionRegion(identity, content: printed)
        }
    }

    /// The mangled name of `name`, the identity a host names the definition
    /// by — or `nil` when it does not remangle, or carries a control
    /// character, which a region identity cannot. Left unmarked, such a child
    /// is printed on its own by the host, as without marking.
    private func definitionRegionIdentity(of name: NodeReference) async -> String? {
        guard let mangledName = try? await mangleAsString(name),
              !mangledName.isEmpty,
              !mangledName.unicodeScalars.contains(where: { $0.value < 0x20 })
        else {
            return nil
        }
        return mangledName
    }
}
