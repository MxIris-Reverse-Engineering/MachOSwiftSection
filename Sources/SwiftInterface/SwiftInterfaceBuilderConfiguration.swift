import MemberwiseInit

/// Configuration options for the Swift interface builder.
/// This configuration allows customization of how Swift interfaces are generated from Mach-O binaries.
@MemberwiseInit(.public)
public struct SwiftInterfaceBuilderConfiguration: Sendable {
    /// Enables type indexing for better type resolution and cross-referencing.
    /// When enabled, the builder will create a type database to resolve types more accurately.
    public var isEnabledTypeIndexing: Bool = false

    public var showCImportedTypes: Bool = false
}
