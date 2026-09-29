// The reader / resolver / pointer layer as one import — everything the ABI
// model (`MachOSwiftSection`) is allowed to depend on, and nothing above it.
// `MachOFoundation` re-exports this plus the symbol index and dependency
// resolution; the ABI layer deliberately stops here (evolution proposal
// `self-contained-abi-layer`).
@_exported import MachOKitExtensions
@_exported import MachOReading
@_exported import MachOResolving
@_exported import MachOPointers
@_exported import Utilities
