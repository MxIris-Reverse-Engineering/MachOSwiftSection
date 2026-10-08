import MachOSwiftSection

package struct DumperMetadataContext<Metadata: MetadataProtocol> {
    package let metadata: Metadata
    package let readingContext: any ReadingContext
}

extension DumperMetadataContext {
    /// Resolve the carried metadata into a `MetadataWrapper` through *this
    /// context's* reading context rather than a dumper's `machO`.
    ///
    /// Specialized in-process metadata (built via `MetadataProtocol
    /// .createInProcess`) stores its `offset` as an absolute pointer bit
    /// pattern, and its `readingContext` is `InProcessContext`. Resolving such
    /// metadata against `machO` instead feeds that absolute address into
    /// `MachOImage.readWrapperElement(offset:)` as if it were an image-relative
    /// offset (`image base + absolute address`), dereferencing a wild pointer
    /// and trapping with `SIGBUS` — a hardware fault that `try?` cannot catch.
    /// Routing through `readingContext` lets `InProcessContext.addressFromOffset`
    /// reinterpret the offset as the pointer it actually is, while a
    /// `MachOContext` reading context keeps the original image-relative meaning.
    package func resolvedMetadataWrapper() throws -> MetadataWrapper {
        try metadata.asMetadataWrapper(in: readingContext)
    }
}
