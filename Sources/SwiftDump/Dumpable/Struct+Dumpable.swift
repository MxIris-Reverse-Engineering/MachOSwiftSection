import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities

extension Struct: NamedDumpable {
    public func dumpName<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try StructDumper(self, options: options, in: machO).name
    }

    public func dump<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try StructDumper(self, options: options, in: machO).body
    }
}
