import Foundation
import MachOKit
import MachODependencies
import MachOSwiftSection
import MachOFoundation
import SwiftLayout
import Demangling
@_spi(Internals) import SwiftInspection

/// How the static (MachOFile) field-layout path resolves field / superclass /
/// protocol types that live in *other* images.
public enum StaticLayoutDependencyResolution: Sendable, Equatable, Hashable {
    /// Resolve only types defined in the binary being rendered. Cross-module
    /// field types degrade (no end offset / type layout), and a resilient class
    /// with a cross-module superclass cannot place its own fields.
    case singleImage
    /// Resolve across the binary's transitive dependency closure, located
    /// through the given search paths (the system dyld shared cache covers the
    /// stdlib / Foundation / the rest of the OS); a binary read out of a dyld
    /// cache resolves in that cache first. Cross-module field /
    /// superclass / protocol types resolve, and resilient classes are laid out
    /// against their dependencies' actual binaries ("this specific deployment").
    case dependencyClosure(searchPaths: [DependencySearchPath])

    /// The default resolution: the full transitive closure over the system dyld
    /// shared cache.
    public static let `default`: StaticLayoutDependencyResolution = .dependencyClosure(searchPaths: [.systemDyldSharedCache])
}

/// The seam the `FieldLayoutRenderer` MachOFile path uses to obtain statically
/// computed field layouts from `SwiftLayout`.
///
/// Reader-agnostic and non-generic so it can ride along inside the (non-generic)
/// `DeclarationRenderConfiguration`. The relatively expensive
/// `StaticLayoutCalculator` construction (especially a dependency closure) is
/// therefore done **once per session** at the call site and injected, rather
/// than rebuilt per rendered type.
public protocol StaticFieldLayoutProvider: Sendable {
    /// The per-field static layout of a struct/class descriptor (offsets plus
    /// each field type's own layout), or `nil` when it could not be computed.
    func aggregateFieldLayout(forDescriptor descriptor: TypeContextDescriptorWrapper) -> AggregateFieldLayout?

    /// The whole-type layout (size / stride / alignment / extra inhabitants) of a
    /// field type given its mangled name — used for enum payload sizing.
    func typeLayout(forMangledTypeName mangledTypeName: MangledName) -> StaticTypeLayout?

    /// The whole-type layout of a type given its descriptor — used for an enum's
    /// own size when computing its single-payload layout.
    func typeLayout(forDescriptor descriptor: TypeContextDescriptorWrapper) -> StaticTypeLayout?

    /// The whole-type layout of a field/payload type given its mangled name,
    /// lowered in the context of the descriptor whose record carries it — the
    /// context supplies class-bound generic parameters and the
    /// runtime-instantiation flag, so a generic enum's `Element` payload can
    /// still resolve. Equivalent to `typeLayout(forMangledTypeName:)` for a
    /// non-generic context.
    func typeLayout(forMangledTypeName mangledTypeName: MangledName, inContextOfDescriptor contextDescriptor: TypeContextDescriptorWrapper) -> StaticTypeLayout?

    /// The per-case projection layout of an enum descriptor (payload/tag
    /// regions and per-case tag values), or `nil` when it cannot be computed.
    /// Works for generic enums whose layout is argument-independent
    /// (class-bound payload parameters).
    func enumCaseLayoutResult(forDescriptor descriptor: TypeContextDescriptorWrapper) -> EnumLayoutCalculator.LayoutResult?

    /// The expanded nested-field-offset tree for a field type placed at
    /// `baseOffset`, descending up to `depthLimit` levels.
    func nestedFieldOffsetTree(forMangledTypeName mangledTypeName: MangledName, baseOffset: Int, depthLimit: Int) -> [NestedFieldOffset]

    // The same four queries for an instantiation a `GenericArgumentBinding`
    // describes — an offline specialization's (evolution proposal
    // `offline-generic-specialization`). Each has a default that answers
    // nothing, so a provider written before them keeps compiling and
    // degrades to no comment rather than to an unspecialized one.

    /// The per-field layout of the instantiation `binding` makes of a
    /// struct/class descriptor.
    func aggregateFieldLayout(forDescriptor descriptor: TypeContextDescriptorWrapper, genericArgumentBinding binding: GenericArgumentBinding) -> AggregateFieldLayout?

    /// The whole-type layout of a payload type, lowered in the context of the
    /// instantiation `binding` makes of `contextDescriptor`.
    func typeLayout(forMangledTypeName mangledTypeName: MangledName, inContextOfDescriptor contextDescriptor: TypeContextDescriptorWrapper, genericArgumentBinding binding: GenericArgumentBinding) -> StaticTypeLayout?

    /// The per-case projection layout of the instantiation `binding` makes of
    /// an enum descriptor.
    func enumCaseLayoutResult(forDescriptor descriptor: TypeContextDescriptorWrapper, genericArgumentBinding binding: GenericArgumentBinding) -> EnumLayoutCalculator.LayoutResult?

    /// The expanded nested-field-offset tree for a field type of the
    /// instantiation `binding` describes.
    func nestedFieldOffsetTree(forMangledTypeName mangledTypeName: MangledName, baseOffset: Int, depthLimit: Int, genericArgumentBinding binding: GenericArgumentBinding) -> [NestedFieldOffset]

    /// `node` with every member of a concrete type projected through the
    /// witness records of the images the layouts above are computed over —
    /// `[Swift.Int].Element` read as `Swift.Int` — so a field's printed type
    /// and the layout printed beside it come from the same images. `nil`
    /// when the provider has no images of its own: the caller projects
    /// through its own.
    func projectingConcreteMembers(in node: Node) -> Node?
}

extension StaticFieldLayoutProvider {
    public func projectingConcreteMembers(in node: Node) -> Node? {
        nil
    }

    public func aggregateFieldLayout(forDescriptor descriptor: TypeContextDescriptorWrapper, genericArgumentBinding binding: GenericArgumentBinding) -> AggregateFieldLayout? {
        nil
    }

    public func typeLayout(forMangledTypeName mangledTypeName: MangledName, inContextOfDescriptor contextDescriptor: TypeContextDescriptorWrapper, genericArgumentBinding binding: GenericArgumentBinding) -> StaticTypeLayout? {
        nil
    }

    public func enumCaseLayoutResult(forDescriptor descriptor: TypeContextDescriptorWrapper, genericArgumentBinding binding: GenericArgumentBinding) -> EnumLayoutCalculator.LayoutResult? {
        nil
    }

    public func nestedFieldOffsetTree(forMangledTypeName mangledTypeName: MangledName, baseOffset: Int, depthLimit: Int, genericArgumentBinding binding: GenericArgumentBinding) -> [NestedFieldOffset] {
        []
    }
}

/// The MachOFile-backed provider, wrapping a `StaticLayoutCalculator<MachOFile>`.
///
/// Access is serialized through a lock: the underlying resolver memoizes without
/// internal synchronization, so funneling every calculator call through one lock
/// keeps a provider that is shared across concurrent renders safe.
public final class MachOFileStaticFieldLayoutProvider: StaticFieldLayoutProvider, @unchecked Sendable {
    private let calculator: StaticLayoutCalculator<MachOFile>
    private let lock = NSLock()

    /// Builds the calculator for `machOFile` per `resolution`. Returns `nil` when
    /// the image universe cannot be built — the renderer then degrades exactly as
    /// it did before SwiftLayout was wired in.
    public init?(machOFile: MachOFile, resolution: StaticLayoutDependencyResolution) {
        do {
            switch resolution {
            case .singleImage:
                self.calculator = try StaticLayoutCalculator(machO: machOFile)
            case .dependencyClosure(let searchPaths):
                let imageUniverse = try ImageUniverse.dependencyClosure(root: machOFile, searchPaths: searchPaths)
                self.calculator = StaticLayoutCalculator(imageUniverse: imageUniverse)
            }
        } catch {
            return nil
        }
    }

    public func aggregateFieldLayout(forDescriptor descriptor: TypeContextDescriptorWrapper) -> AggregateFieldLayout? {
        lock.lock()
        defer { lock.unlock() }
        return try? calculator.fieldLayout(of: descriptor)
    }

    public func typeLayout(forMangledTypeName mangledTypeName: MangledName) -> StaticTypeLayout? {
        lock.lock()
        defer { lock.unlock() }
        return try? calculator.typeLayout(forMangledTypeName: mangledTypeName)
    }

    public func typeLayout(forDescriptor descriptor: TypeContextDescriptorWrapper) -> StaticTypeLayout? {
        lock.lock()
        defer { lock.unlock() }
        return try? calculator.typeLayout(forDescriptor: descriptor)
    }

    public func typeLayout(forMangledTypeName mangledTypeName: MangledName, inContextOfDescriptor contextDescriptor: TypeContextDescriptorWrapper) -> StaticTypeLayout? {
        lock.lock()
        defer { lock.unlock() }
        return try? calculator.typeLayout(forMangledTypeName: mangledTypeName, inContextOfDescriptor: contextDescriptor)
    }

    public func enumCaseLayoutResult(forDescriptor descriptor: TypeContextDescriptorWrapper) -> EnumLayoutCalculator.LayoutResult? {
        lock.lock()
        defer { lock.unlock() }
        return calculator.enumCaseLayoutResult(forDescriptor: descriptor)
    }

    public func nestedFieldOffsetTree(forMangledTypeName mangledTypeName: MangledName, baseOffset: Int, depthLimit: Int) -> [NestedFieldOffset] {
        lock.lock()
        defer { lock.unlock() }
        return calculator.nestedFieldOffsetTree(forMangledTypeName: mangledTypeName, baseOffset: baseOffset, depthLimit: depthLimit)
    }

    public func aggregateFieldLayout(forDescriptor descriptor: TypeContextDescriptorWrapper, genericArgumentBinding binding: GenericArgumentBinding) -> AggregateFieldLayout? {
        lock.lock()
        defer { lock.unlock() }
        return try? calculator.fieldLayout(of: descriptor, genericArgumentBinding: binding)
    }

    public func typeLayout(forMangledTypeName mangledTypeName: MangledName, inContextOfDescriptor contextDescriptor: TypeContextDescriptorWrapper, genericArgumentBinding binding: GenericArgumentBinding) -> StaticTypeLayout? {
        lock.lock()
        defer { lock.unlock() }
        return try? calculator.typeLayout(forMangledTypeName: mangledTypeName, inContextOfDescriptor: contextDescriptor, genericArgumentBinding: binding)
    }

    public func enumCaseLayoutResult(forDescriptor descriptor: TypeContextDescriptorWrapper, genericArgumentBinding binding: GenericArgumentBinding) -> EnumLayoutCalculator.LayoutResult? {
        lock.lock()
        defer { lock.unlock() }
        return calculator.enumCaseLayoutResult(forDescriptor: descriptor, genericArgumentBinding: binding)
    }

    public func nestedFieldOffsetTree(forMangledTypeName mangledTypeName: MangledName, baseOffset: Int, depthLimit: Int, genericArgumentBinding binding: GenericArgumentBinding) -> [NestedFieldOffset] {
        lock.lock()
        defer { lock.unlock() }
        return calculator.nestedFieldOffsetTree(forMangledTypeName: mangledTypeName, baseOffset: baseOffset, depthLimit: depthLimit, genericArgumentBinding: binding)
    }

    public func projectingConcreteMembers(in node: Node) -> Node? {
        lock.lock()
        defer { lock.unlock() }
        return calculator.projectingConcreteMembers(in: node)
    }
}
