import MachOKit

public protocol RelativeIndirectType: Resolvable {
    associatedtype Resolved: Resolvable
    func resolve(in machOFile: MachOFile) throws -> Resolved
    func resolveAny<T>(in machOFile: MachOFile) throws -> T
    func resolveOffset(in machOFile: MachOFile) -> Int
}
