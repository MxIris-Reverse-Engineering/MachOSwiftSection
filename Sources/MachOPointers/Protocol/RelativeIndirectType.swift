import MachOKit
import MachOReading
import MachOResolving
import MachOExtensions

public protocol RelativeIndirectType<Resolved>: Resolvable {
    associatedtype Resolved: Resolvable
    
    func resolve<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> Resolved
    func resolveAny<T: Resolvable, MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> T
    func resolveOffset<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) -> Int
}
