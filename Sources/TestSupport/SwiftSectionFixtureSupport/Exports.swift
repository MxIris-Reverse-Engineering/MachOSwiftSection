// The Swift-free test support shared with MachOKitExtensions: fixture names,
// opening caches and images, slice picking, the fixture compiler and
// `.print()`. Re-exported so that a test importing this module reaches it
// without an import of its own; this module adds the package's own fixture
// names and named caches to it (`MachOFileName+SymbolTests.swift`,
// `MachOImageName+SymbolTests.swift`, `DyldSharedCachePath+NamedCaches.swift`).
@_exported import MachOFixtureSupport
