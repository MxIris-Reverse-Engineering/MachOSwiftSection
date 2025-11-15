import Semantic
import Demangling
import MachOKit
import MachOSwiftSection
import Utilities

extension Class: NamedDumpable {
    public func dumpName<MachO: MachOSwiftSectionRepresentableWithCache>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString {
        try await ClassDumper(self, using: configuration, in: machO).name
    }

    public func dump<MachO: MachOSwiftSectionRepresentableWithCache>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString {
        try await ClassDumper(self, using: configuration, in: machO).body
    }
}
