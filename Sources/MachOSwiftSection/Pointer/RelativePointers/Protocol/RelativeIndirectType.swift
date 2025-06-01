import MachOKit
import MachOFoundation

public protocol RelativeIndirectType: Resolvable {
    associatedtype Resolved: Resolvable
    
    func resolve(in machOFile: MachOFile) throws -> Resolved
    func resolveAny<T>(in machOFile: MachOFile) throws -> T
    func resolveOffset(in machOFile: MachOFile) -> Int
    
    func resolve(in machOImage: MachOImage) throws -> Resolved
    func resolveAny<T>(in machOImage: MachOImage) throws -> T
    func resolveOffset(in machOImage: MachOImage) -> Int
}
