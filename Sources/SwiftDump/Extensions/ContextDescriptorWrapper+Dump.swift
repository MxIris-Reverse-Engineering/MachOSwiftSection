import MachOKit
import MachOMacro
import MachOSwiftSection

extension ContextDescriptorWrapper {
    @MachOImageGenerator
    package func dumpName(using options: DemangleOptions, in machOFile: MachOFile) throws -> String {
        try MetadataReader.demangleContext(for: self, in: machOFile).print(using: options)
    }
}
