import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities

extension AssociatedType: ConformedDumpable {
    public func dumpTypeName<MachO: MachOSwiftSectionRepresentableWithCache>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString {
        try await AssociatedTypeDumper(self, using: configuration, in: machO).typeName
    }

    public func dumpProtocolName<MachO: MachOSwiftSectionRepresentableWithCache>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString {
        try await AssociatedTypeDumper(self, using: configuration, in: machO).protocolName
    }

    public func dump<MachO: MachOSwiftSectionRepresentableWithCache>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString {
        try await AssociatedTypeDumper(self, using: configuration, in: machO).body
    }
}
