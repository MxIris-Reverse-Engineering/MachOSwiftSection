import MachOKitExtensions
import SwiftDeclarationRendering

/// A wrapper that declares what it wraps can say so to the library: the
/// library then asks the reader beneath it whatever it needs to know about the
/// reader.
extension ForwardingMachOReader: MachOReaderWrapper where Declaration == DeclaredWrapper {}

/// The printers take a reader that renders its own field-layout comments; a
/// declared wrapper renders them through the reader it wraps, with nothing
/// written here.
extension ForwardingMachOReader: FieldLayoutRenderable where Base: FieldLayoutRenderable, Declaration == DeclaredWrapper {}
