import Semantic

protocol ConformedDumper: Dumper {
    @SemanticStringBuilder var typeName: SemanticString { get async throws }
    @SemanticStringBuilder var protocolName: SemanticString { get async throws }
}
