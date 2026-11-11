import MachOKit
import MachOReading
import MachOResolving
import MachOKitExtensions

public protocol RelativePointerProtocol<Pointee>: Sendable, Equatable {
    associatedtype Pointee: Resolvable
    associatedtype Offset: FixedWidthInteger & SignedInteger

    var relativeOffset: Offset { get }

    func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Pointee

    func resolveAny<T: Resolvable, Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> T

    func resolveDirectOffset(from offset: Int) -> Int
    func resolveDirectAddress<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Context.Address

}

extension RelativePointerProtocol {
    public func resolveDirectOffset(from offset: Int) -> Int {
        return Int(offset) + Int(relativeOffset)
    }

    public func resolveDirectAddress<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Context.Address {
        return context.advanceAddress(address, by: .init(relativeOffset))
    }

    public var isNull: Bool {
        return relativeOffset == 0
    }

    public var isValid: Bool {
        return relativeOffset != 0
    }
}
