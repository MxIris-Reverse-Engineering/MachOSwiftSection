import Foundation
import MachOKit
import MachOBase

/// A record in `__swift5_acfuncs`: a function that can be found again by
/// string key at runtime and then called with arguments assembled
/// dynamically.
///
/// The runtime cannot call an arbitrary Swift function from data alone — the
/// calling convention depends on the signature. So for the functions that do
/// need to be reached that way the compiler emits a **fully abstracted**
/// entry point (everything passed indirectly, one uniform shape) and records
/// it here alongside the key that names it and the mangled Swift type that
/// says what the arguments mean. Today the feature's user is distributed
/// actors: a remote call arrives carrying a target identifier string, and
/// `swift_findAccessibleFunction` is what turns that string back into
/// something callable.
///
/// Layout mirrors `swift::TargetAccessibleFunctionRecord`
/// (`swift/ABI/Metadata.h`): four relative pointers and a flag word, 20
/// bytes, laid end to end across the section — the runtime slices the
/// section by `begin + size` with no header
/// (`stdlib/public/runtime/AccessibleFunction.cpp`), and so does this
/// library.
///
/// A module that needs none of this emits no section at all, so
/// `swift.accessibleFunctionRecords` throws
/// `MachOSwiftSectionError.sectionNotFound` rather than answering empty —
/// the same contract as every other section accessor here.
@LocatableLayoutWrapping
public struct AccessibleFunctionRecord: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let name: RelativeDirectPointer<String>
        /// Null for a non-generic function — the only nullable pointer here.
        public let genericEnvironment: RelativeDirectRawPointer
        public let functionType: RelativeDirectPointer<MangledName>
        /// The fully abstracted entry point. Non-nullable in the ABI.
        public let function: RelativeDirectRawPointer
        public let flags: AccessibleFunctionFlags
    }
}

extension AccessibleFunctionRecord {
    /// Whether this is a `distributed` actor function.
    public var isDistributed: Bool { layout.flags.contains(.isDistributed) }
}

// MARK: - MachO Reading

extension AccessibleFunctionRecord {
    /// The lookup key the runtime matches an incoming call target against.
    /// Not a mangled name in the demangler's sense — it is whatever string
    /// the emitter chose, so it is read as a plain C string.
    public func name<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> String {
        try layout.name.resolve(from: offset(of: \.name), in: machO)
    }

    /// The function's Swift type, mangled. This is what tells a caller how to
    /// build the arguments the abstracted entry point expects.
    public func functionType<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> MangledName {
        try layout.functionType.resolve(from: offset(of: \.functionType), in: machO)
    }

    /// The generic environment describing the function's generic signature,
    /// or `nil` for a non-generic function — the only nullable pointer in the
    /// record.
    public func genericEnvironment<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> GenericEnvironment? {
        guard let genericEnvironmentOffset = resolvedDirectOffset(from: \.genericEnvironment) else { return nil }
        return try GenericEnvironment.resolve(from: genericEnvironmentOffset, in: machO)
    }
}

extension AccessibleFunctionRecord {
    public func name() throws -> String {
        try layout.name.resolve(from: pointer(of: \.name))
    }

    public func functionType() throws -> MangledName {
        try layout.functionType.resolve(from: pointer(of: \.functionType))
    }
}

// MARK: - ReadingContext Support

extension AccessibleFunctionRecord {
    public func name<Context: ReadingContext>(in context: Context) throws -> String {
        try layout.name.resolve(at: try context.addressFromOffset(offset(of: \.name)), in: context)
    }

    public func functionType<Context: ReadingContext>(in context: Context) throws -> MangledName {
        try layout.functionType.resolve(at: try context.addressFromOffset(offset(of: \.functionType)), in: context)
    }

    /// The entry point's location as an address in `context` (a file offset
    /// for `MachOContext`, a pointer in-process). The pointer is non-nullable
    /// in the ABI, so `nil` means the record is malformed.
    public func functionAddress<Context: ReadingContext>(in context: Context) throws -> Context.Address? {
        guard let functionOffset = resolvedDirectOffset(from: \.function) else { return nil }
        return try context.addressFromOffset(functionOffset)
    }
}
