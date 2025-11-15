import MachOKit
import Semantic
import MachOSwiftSection

public protocol NamedDumpable: Dumpable {
    func dumpName<MachO: MachOSwiftSectionRepresentableWithCache>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString
}
