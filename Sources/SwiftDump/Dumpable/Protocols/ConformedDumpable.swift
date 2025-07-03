import MachOKit
import Semantic
import MachOFoundation

public protocol ConformedDumpable: Dumpable {
    func dumpTypeName<MachO: MachORepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString
    func dumpProtocolName<MachO: MachORepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString
}
