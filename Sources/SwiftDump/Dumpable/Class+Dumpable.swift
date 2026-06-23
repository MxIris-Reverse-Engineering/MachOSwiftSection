import Semantic
import Demangling
import MachOKit
import MachOSwiftSection
import Utilities
import SwiftDeclarationRendering

extension Class: NamedDumpable {
    public func dumpName<MachO: FieldLayoutRenderable>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString {
        try await ClassDumper(self, using: configuration, in: machO).name
    }

    public func dump<MachO: FieldLayoutRenderable>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString {
        try await ClassDumper(self, using: configuration, in: machO).body
    }
}
