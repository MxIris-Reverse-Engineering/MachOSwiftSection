import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Demangling
import Utilities
import OrderedCollections

extension ProtocolConformance: ConformedDumpable {
    public func dumpTypeName<MachO: MachOSwiftSectionRepresentableWithCache>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString {
        try await ProtocolConformanceDumper(self, using: configuration, in: machO).typeName
    }

    public func dumpProtocolName<MachO: MachOSwiftSectionRepresentableWithCache>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString {
        try await ProtocolConformanceDumper(self, using: configuration, in: machO).protocolName
    }

    public func dump<MachO: MachOSwiftSectionRepresentableWithCache>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString {
        try await ProtocolConformanceDumper(self, using: configuration, in: machO).body
    }
}
