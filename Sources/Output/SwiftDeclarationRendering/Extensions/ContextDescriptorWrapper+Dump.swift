import MachOKit
import MachOSwiftSection
import Semantic
import Demangling
@_spi(Internals) import SwiftInspection

extension ContextDescriptorWrapper {
    package func dumpName(using options: DemangleOptions, in context: some ReadingContext) throws -> SemanticString {
        try dumpNameNode(in: context).printSemantic(using: options)
    }

    package func dumpNameNode(in context: some ReadingContext) throws -> Node {
        try SymbolicDemangler.demangleContext(for: self, in: context)
    }
}
