import Foundation
import MachOKit

public protocol RelativePointer<Pointee> {
    associatedtype Pointee: ResolvableElement
    associatedtype Offset: FixedWidthInteger & SignedInteger
    var relativeOffset: Offset { get }
    func resolve(from fileOffset: Int, in machO: MachOFile) throws -> Pointee
    func resolve<T>(from fileOffset: Int, in machO: MachOFile) throws -> T
    func resolveDirectFileOffset(from fileOffset: Int) -> Int
}

extension RelativePointer {
    public func resolveDirectFileOffset(from fileOffset: Int) -> Int {
        return Int(fileOffset) + Int(relativeOffset)
    }

    public var isNull: Bool {
        return relativeOffset == 0
    }

    public var isValid: Bool {
        return relativeOffset != 0
    }
}

func read<T>(offset fileOffset: Int, in machO: MachOFile) throws -> T {
    return try machO.readElement(offset: fileOffset)
}
