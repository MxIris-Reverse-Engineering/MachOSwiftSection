import MachOKit
import MachOSwiftSection
import Semantic
import Demangling
@_spi(Internals) import SwiftInspection

extension ContextDescriptorWrapper {
    package func dumpName(using options: DemangleOptions, in machO: some MachOSwiftSectionRepresentableWithCache) throws -> SemanticString {
        try dumpNameNode(in: machO).printSemantic(using: options)
    }

    package func dumpNameNode(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> Node {
        try SymbolicDemangler.demangleContext(for: self, in: machO)
    }
}
