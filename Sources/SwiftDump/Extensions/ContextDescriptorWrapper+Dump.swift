import MachOKit
import MachOMacro
import MachOFoundation
import MachOSwiftSection
import Semantic

extension ContextDescriptorWrapper {
    package func dumpName<MachO: MachORepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try MetadataReader.demangleContext(for: self, in: machO).printSemantic(using: options)
    }
}
