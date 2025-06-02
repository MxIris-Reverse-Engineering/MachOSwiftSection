import Foundation
import MachOKit
import MachOSwiftSection
import MachOMacro

extension ContextDescriptorWrapper {
    @MachOImageGenerator
    func dumpName(using options: SymbolPrintOptions, in machOFile: MachOFile) throws -> String {
        try MetadataReader.demangleContext(for: self, in: machOFile).print(using: options)
    }
}
