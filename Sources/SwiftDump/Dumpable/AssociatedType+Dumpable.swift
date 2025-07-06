import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities

extension AssociatedType: ConformedDumpable {
    public func dumpTypeName<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try AssociatedTypeDumper(associatedType: self, options: options, machO: machO).typeName
    }

    public func dumpProtocolName<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try AssociatedTypeDumper(associatedType: self, options: options, machO: machO).protocolName
    }

    public func dump<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try AssociatedTypeDumper(associatedType: self, options: options, machO: machO).body
    }
}
