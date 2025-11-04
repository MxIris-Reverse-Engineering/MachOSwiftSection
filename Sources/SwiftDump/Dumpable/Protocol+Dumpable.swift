import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities
import Demangling
import OrderedCollections

extension MachOSwiftSection.`Protocol`: NamedDumpable {
    public func dumpName<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) async throws -> SemanticString {
        try await ProtocolDumper(self, using: .init(demangleResolver: .using(options: options)), in: machO).name
    }

    public func dump<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) async throws -> SemanticString {
        try await ProtocolDumper(self, using: .init(demangleResolver: .using(options: options)), in: machO).body
    }
}
