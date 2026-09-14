import Semantic
import Demangling
import MachOKit
import MachOSwiftSection
import MachOFoundation
import Utilities
import SwiftDeclarationRendering

extension Class: NamedDumpable {
    public func dumpName<MachO: MachOFieldLayoutRenderable>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString {
        try await ClassDumper(self, using: configuration, in: machO).name
    }

    public func dump<MachO: MachOFieldLayoutRenderable>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString {
        try await LargeStackTaskExecution.run {
            try await ClassDumper(self, using: configuration, in: machO).body
        }
    }
}
