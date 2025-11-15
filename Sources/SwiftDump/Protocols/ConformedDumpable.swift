import MachOKit
import Semantic
import MachOSwiftSection

public protocol ConformedDumpable: Dumpable {
    func dumpTypeName<MachO: MachOSwiftSectionRepresentableWithCache>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString
    func dumpProtocolName<MachO: MachOSwiftSectionRepresentableWithCache>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString
}
