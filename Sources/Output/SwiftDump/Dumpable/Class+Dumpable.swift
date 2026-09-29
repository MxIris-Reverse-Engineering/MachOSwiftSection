import Semantic
import Demangling
import MachOKit
import MachOSwiftSection
import MachOFoundation
import Utilities
import SwiftDeclarationRendering

extension Class: NamedDumpable {
    public func dumpName(using configuration: DumperConfiguration, in machO: some MachOFieldLayoutRenderable) async throws -> SemanticString {
        try await ClassDumper(self, using: configuration, in: machO).name
    }

    public func dump(using configuration: DumperConfiguration, in machO: some MachOFieldLayoutRenderable) async throws -> SemanticString {
        try await LargeStackTaskExecution.run {
            try await ClassDumper(self, using: configuration, in: machO).body
        }
    }
}
