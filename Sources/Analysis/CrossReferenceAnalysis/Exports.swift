// The layers below the Swift one: what they define publicly is part of this
// module's public face, as it was before the analysis was split into layers
// (`CodeLocation`, `CodeReferenceKind`, `IndirectCallEvidence`,
// `ReceiverClassHint`). Their `@_spi(Internals)` interfaces are imported
// file by file, and are not re-exported.
@_exported import MachOCodeReferences
@_exported import CrossReferenceObjC
