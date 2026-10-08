import MachOKit
import MachOReading
import MachOResolving
import MachOKitExtensions

public protocol RelativeIndirectType<Resolved>: Resolvable {
    associatedtype Resolved: Resolvable

    func resolve(in context: some ReadingContext) throws -> Resolved
    func resolveAny<T: Resolvable>(in context: some ReadingContext) throws -> T
    func resolveAddress<Context: ReadingContext>(in context: Context) throws -> Context.Address

    // The deprecated forms stay requirements for the reason given in
    // `PointerProtocol`: `Pointer` conforms to both protocols.
    @available(*, deprecated, message: "Pass a ReadingContext: resolve(in: machO.context).")
    func resolve(in machO: some MachORepresentableWithCache & Readable) throws -> Resolved
    @available(*, deprecated, message: "Pass a ReadingContext: resolveAny(in: machO.context).")
    func resolveAny<T: Resolvable>(in machO: some MachORepresentableWithCache & Readable) throws -> T
    @available(*, deprecated, message: "Pass a ReadingContext: resolveAddress(in: machO.context).")
    func resolveOffset(in machO: some MachORepresentableWithCache & Readable) -> Int

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(in: .inProcess).")
    func resolve() throws -> Resolved
    @available(*, deprecated, message: "Pass a ReadingContext: resolveAny(in: .inProcess).")
    func resolveAny<T: Resolvable>() throws -> T
}
