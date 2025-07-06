import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities
import Demangle
import OrderedCollections

extension MachOSwiftSection.`Protocol`: NamedDumpable {
    public func dumpName<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try ProtocolDumper(protocol: self, options: options, machO: machO).name
    }

    public func dump<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try ProtocolDumper(protocol: self, options: options, machO: machO).body
    }
}
