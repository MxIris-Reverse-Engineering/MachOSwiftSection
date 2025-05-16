import MachOKit

public protocol RelativeIndirectType {
    associatedtype Pointee: ResolvableElement
    func resolve(in machOFile: MachOFile) throws -> Pointee
    func resolveAny<T>(in machOFile: MachOFile) throws -> T
    func resolveOffset(in machOFile: MachOFile) -> Int
}
