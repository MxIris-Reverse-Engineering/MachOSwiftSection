import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities

extension AssociatedType: ConformedDumpable {
    public func dumpTypeName<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try AssociatedTypeDumper(self, using: .init(demangleOptions: options), in: machO).typeName
    }

    public func dumpProtocolName<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try AssociatedTypeDumper(self, using: .init(demangleOptions: options), in: machO).protocolName
    }

    public func dump<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try AssociatedTypeDumper(self, using: .init(demangleOptions: options), in: machO).body
    }
}
