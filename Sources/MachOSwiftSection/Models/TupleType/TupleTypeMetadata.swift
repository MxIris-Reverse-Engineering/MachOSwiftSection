import Foundation
import MachOFoundation

public struct TupleTypeMetadata: MetadataProtocol {
    public typealias HeaderType = TypeMetadataHeaderBase
    public struct Element: TupleTypeMetadataElementLayout {
        public let type: ConstMetadataPointer<Metadata>
        public let offset: StoredSize
    }

    public struct Layout: TupleTypeMetadataLayout {
        public let kind: StoredPointer
        public let numberOfElements: StoredSize
        public let labels: Pointer<String>
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}

extension TupleTypeMetadata {
    public func elements<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> [Element] {
        try machO.readElements(offset: offset + layoutSize, numberOfElements: layout.numberOfElements.cast())
    }
}
