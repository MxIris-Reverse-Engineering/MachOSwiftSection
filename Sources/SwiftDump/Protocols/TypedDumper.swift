import Semantic
import MachOSwiftSection

package protocol TypedDumper: NamedDumper where Dumped: TopLevelType, Dumped.Descriptor: TypeContextDescriptorProtocol {
    associatedtype Metadata: MetadataProtocol
    @SemanticStringBuilder var fields: SemanticString { get async throws }
    
    init(_ dumped: Dumped, metadata: Metadata?, using configuration: DumperConfiguration, in machO: MachO)
}

extension TypedDumper {
    package var typeLayout: TypeLayout? {
        get throws {
            try dumped.descriptor.metadataAccessorFunction(in: machO)?(request: .init()).value.resolve(in: machO).valueWitnessTable(in: machO).typeLayout
        }
    }
}
