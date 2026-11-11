import MachOKit
import MachOReading
import MachOResolving
import MachOKitExtensions

public protocol RelativeIndirectType<Resolved>: Resolvable {
    associatedtype Resolved: Resolvable

    func resolve(in context: some ReadingContext) throws -> Resolved
    func resolveAny<T: Resolvable>(in context: some ReadingContext) throws -> T
    func resolveAddress<Context: ReadingContext>(in context: Context) throws -> Context.Address
}
