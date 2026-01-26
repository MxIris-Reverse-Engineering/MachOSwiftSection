import MachOKit
import MachOReading
import MachOResolving
import MachOExtensions

public protocol RelativeIndirectType<Resolved>: Resolvable {
    associatedtype Resolved: Resolvable

    func resolve<MachO: MachORepresentableWithCache & Readable>(in machO: MachO) throws -> Resolved
    func resolveAny<T: Resolvable, MachO: MachORepresentableWithCache & Readable>(in machO: MachO) throws -> T
    func resolveOffset<MachO: MachORepresentableWithCache & Readable>(in machO: MachO) -> Int

    func resolve() throws -> Resolved
    func resolveAny<T: Resolvable>() throws -> T

    func resolve<Context: ReadingContext>(in context: Context) throws -> Resolved
    func resolveAny<T: Resolvable, Context: ReadingContext>(in context: Context) throws -> T
    func resolveAddress<Context: ReadingContext>(in context: Context) throws -> Context.Address
}
