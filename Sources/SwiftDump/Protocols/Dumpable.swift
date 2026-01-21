import Demangling
import MachOKit
import Semantic
import MachOSwiftSection

public typealias DemangleOptions = Demangling.DemangleOptions

public protocol Dumpable: Sendable {
    func dump<MachO: MachOSwiftSectionRepresentableWithCache>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString
}
