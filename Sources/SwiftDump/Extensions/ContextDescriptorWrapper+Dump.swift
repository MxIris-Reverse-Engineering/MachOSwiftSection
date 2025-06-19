import MachOKit
import MachOMacro
import MachOSwiftSection
import Semantic

extension ContextDescriptorWrapper {
    @MachOImageGenerator
    package func dumpName(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        try MetadataReader.demangleContext(for: self, in: machOFile).printSemantic(using: options)
    }
}
