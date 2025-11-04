import Semantic

package protocol TypedDumper: NamedDumper {
    @SemanticStringBuilder var fields: SemanticString { get async throws }
}
