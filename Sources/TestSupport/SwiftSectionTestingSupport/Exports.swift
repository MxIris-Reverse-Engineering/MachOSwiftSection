// The Testing half of the test support shared with MachOKitExtensions:
// `ExclusiveImageAccess`, the `MachOFileTests`, `MachOImageTests`,
// `DyldCacheTests`, `XcodeMachOFileTests` and `MachOFixtureTests` base
// classes. Re-exported so that a test importing this module reaches them
// without an import of its own.
@_exported import MachOTestingSupport
// The Swift-free half too: `ForwardingMachOReader` takes its
// `DeclaredWrapper` / `UndeclaredWrapper` markers from it, so a test naming
// one through this module alone still finds it.
@_exported import MachOFixtureSupport
