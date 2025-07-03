import MachOKit
import Semantic
import MachOFoundation
import MachOSwiftSection

public protocol ConformedDumpable: Dumpable {
    func dumpTypeName<MachO: MachOSwiftSectionRepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString
    func dumpProtocolName<MachO: MachOSwiftSectionRepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString
}
