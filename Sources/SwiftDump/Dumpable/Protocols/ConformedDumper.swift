import Semantic

protocol ConformedDumper: Dumper {
    @SemanticStringBuilder var typeName: SemanticString { get throws }
    @SemanticStringBuilder var protocolName: SemanticString { get throws }
}
