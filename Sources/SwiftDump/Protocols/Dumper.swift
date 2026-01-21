import Semantic
import MachOSwiftSection

package protocol Dumper: Sendable {
    associatedtype Dumped: Sendable
    associatedtype MachO: MachOSwiftSectionRepresentableWithCache

    var dumped: Dumped { get }
    var configuration: DumperConfiguration { get }
    var machO: MachO { get }
    
    @SemanticStringBuilder var declaration: SemanticString { get async throws }
    @SemanticStringBuilder var body: SemanticString { get async throws }

    init(_ dumped: Dumped, using configuration: DumperConfiguration, in machO: MachO)
}
