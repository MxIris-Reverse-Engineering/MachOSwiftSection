@_exported import MachOBase
// `MachOBase` moved to MachOKitExtensions without MachOSwiftSection's own
// `Utilities`; the ABI model re-exports it, so a downstream that reached
// `Utilities` through this module still does.
@_exported import Utilities
