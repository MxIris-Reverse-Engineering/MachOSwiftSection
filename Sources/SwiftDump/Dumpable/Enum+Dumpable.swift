import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities

extension Enum: NamedDumpable {
    public func dumpName<MachO: MachOSwiftSectionRepresentableWithCache>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString {
        try await EnumDumper(self, using: configuration, in: machO).name
    }

    public func dump<MachO: MachOSwiftSectionRepresentableWithCache>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString {
        try await EnumDumper(self, using: configuration, in: machO).body
    }
}
