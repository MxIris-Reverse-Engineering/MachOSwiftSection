import Foundation
import MachOBase

@LocatableLayoutWrapping
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
}

// MARK: - ReadingContext Support

extension TupleTypeMetadata {
    public func elements(in context: some ReadingContext) throws -> [Element] {
        try context.readElements(at: try context.addressFromOffset(offset + layoutSize), numberOfElements: layout.numberOfElements.cast())
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension TupleTypeMetadata {
    @available(*, deprecated, message: "Pass a ReadingContext: elements(in: machO.context).")
    public func elements(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> [Element] {
        try elements(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: elements(in: .inProcess).")
    public func elements() throws -> [Element] {
        try elements(in: InProcessContext.shared)
    }
}
