import MachOKit
import Semantic
import MachOSwiftSection

public protocol ConformedDumpable: Dumpable {
    func dumpTypeName<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString
    func dumpProtocolName<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString
}
