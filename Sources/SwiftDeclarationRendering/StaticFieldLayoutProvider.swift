import Foundation
import MachOKit
import MachOSwiftSection
import SwiftLayout

/// How the static (MachOFile) field-layout path resolves field / superclass /
/// protocol types that live in *other* images.
public enum StaticLayoutDependencyResolution: Sendable, Equatable, Hashable {
    /// Resolve only types defined in the binary being rendered. Cross-module
    /// field types degrade (no end offset / type layout), and a resilient class
    /// with a cross-module superclass cannot place its own fields.
    case singleImage
    /// Resolve across the binary's transitive dependency closure, located
    /// through the given search paths (the system dyld shared cache covers the
    /// stdlib / Foundation / the rest of the OS). Cross-module field /
    /// superclass / protocol types resolve, and resilient classes are laid out
    /// against their dependencies' actual binaries ("this specific deployment").
    case dependencyClosure(searchPaths: [LayoutDependencySearchPath])

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

    /// The expanded nested-field-offset tree for a field type placed at
    /// `baseOffset`, descending up to `depthLimit` levels.
    func nestedFieldOffsetTree(forMangledTypeName mangledTypeName: MangledName, baseOffset: Int, depthLimit: Int) -> [NestedFieldOffset]
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

    public func nestedFieldOffsetTree(forMangledTypeName mangledTypeName: MangledName, baseOffset: Int, depthLimit: Int) -> [NestedFieldOffset] {
        lock.lock()
        defer { lock.unlock() }
        return calculator.nestedFieldOffsetTree(forMangledTypeName: mangledTypeName, baseOffset: baseOffset, depthLimit: depthLimit)
    }
}
