import MachOKit
import MachOSwiftSection
import Semantic

extension ContextDescriptorWrapper {
    package func dumpName<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try MetadataReader.demangleContext(for: self, in: machO).printSemantic(using: options)
    }
}
