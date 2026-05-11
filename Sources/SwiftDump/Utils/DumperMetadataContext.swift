import MachOSwiftSection

package struct DumperMetadataContext<Metadata: MetadataProtocol> {
    package let metadata: Metadata
    package let readingContext: any ReadingContext
}
