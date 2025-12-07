import MachOKit
import MachOSwiftSection
import Semantic
import Demangling
import SwiftInspection

extension ContextDescriptorWrapper {
    package func dumpName<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try dumpNameNode(in: machO).printSemantic(using: options)
    }

    package func dumpNameNode<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> Node {
        try MetadataReader.demangleContext(for: self, in: machO)
    }
}
