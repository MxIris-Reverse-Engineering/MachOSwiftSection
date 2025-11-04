import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities
import MemberwiseInit
import Demangling

package enum DemangleResolver {
    case options(DemangleOptions)
    case builder((Node) async throws -> SemanticString)

    package static func using(options: DemangleOptions) -> DemangleResolver {
        .options(options)
    }

    package static func using(@SemanticStringBuilder builder: @escaping (Node) async throws -> SemanticString) -> DemangleResolver {
        .builder(builder)
    }

    func resolve(for node: Node) async throws -> SemanticString {
        switch self {
        case .options(let options):
            return node.printSemantic(using: options)
        case .builder(let builder):
            return try await builder(node)
        }
    }

    func modify(_ modifier: (DemangleResolver) -> DemangleResolver) -> DemangleResolver {
        modifier(self)
    }
}
