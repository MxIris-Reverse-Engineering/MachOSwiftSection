import Demangling
import MachOKit
import Semantic
import MachOSwiftSection

public typealias DemangleOptions = Demangling.DemangleOptions

public protocol Dumpable {
    func dump<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString
}




