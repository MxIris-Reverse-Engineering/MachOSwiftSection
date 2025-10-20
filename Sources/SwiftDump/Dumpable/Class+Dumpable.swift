import Semantic
import Demangling
import MachOKit
import MachOSwiftSection
import Utilities

extension Class: NamedDumpable {
    public func dumpName<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try ClassDumper(self, using: .init(demangleResolver: .using(options: options)), in: machO).name
    }

    public func dump<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try ClassDumper(self, using: .init(demangleResolver: .using(options: options)), in: machO).body
    }
}
