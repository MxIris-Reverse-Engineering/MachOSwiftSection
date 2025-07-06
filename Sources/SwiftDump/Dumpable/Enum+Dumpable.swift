import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities

extension Enum: NamedDumpable {
    public func dumpName<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try EnumDumper(enum: self, options: options, machO: machO).name
    }

    public func dump<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try EnumDumper(enum: self, options: options, machO: machO).body
    }
}
