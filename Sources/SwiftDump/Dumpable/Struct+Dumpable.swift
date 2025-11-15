import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities

extension Struct: NamedDumpable {
    public func dumpName<MachO: MachOSwiftSectionRepresentableWithCache>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString {
        try await StructDumper(self, using: configuration, in: machO).name
    }

    public func dump<MachO: MachOSwiftSectionRepresentableWithCache>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString {
        try await StructDumper(self, using: configuration, in: machO).body
    }
}
