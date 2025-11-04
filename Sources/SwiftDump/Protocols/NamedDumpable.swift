import MachOKit
import Semantic
import MachOSwiftSection

public protocol NamedDumpable: Dumpable {
    func dumpName<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) async throws -> SemanticString
}
