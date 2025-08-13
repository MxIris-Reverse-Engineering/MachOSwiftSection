import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Demangle
import Utilities
import OrderedCollections

extension ProtocolConformance: ConformedDumpable {
    public func dumpTypeName<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try ProtocolConformanceDumper(self, options: options, in: machO).typeName
    }

    public func dumpProtocolName<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try ProtocolConformanceDumper(self, options: options, in: machO).protocolName
    }

    public func dump<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try ProtocolConformanceDumper(self, options: options, in: machO).body
    }
}
