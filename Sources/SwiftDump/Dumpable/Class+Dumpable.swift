import Semantic
import Demangle
import MachOKit
import MachOSwiftSection
import Utilities

extension Class: NamedDumpable {
    public func dumpName<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try ClassDumper(class: self, options: options, machO: machO).name
    }

    public func dump<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try ClassDumper(class: self, options: options, machO: machO).body
    }
}
