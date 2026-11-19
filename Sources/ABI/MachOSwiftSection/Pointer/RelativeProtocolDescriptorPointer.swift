import MachOKit
import MachOBase

public enum RelativeProtocolDescriptorPointer: Sendable, Equatable {
    case objcPointer(RelativeSymbolOrElementPointerIntPair<ObjCProtocolPrefix, Bit>)
    case swiftPointer(RelativeSymbolOrElementPointerIntPair<ProtocolDescriptor, Bit>)

    public var isObjC: Bool {
        switch self {
        case .objcPointer:
            return true
        case .swiftPointer:
            return false
        }
    }

    public var rawPointer: RelativeIndirectableRawPointerIntPair<Bit> {
        switch self {
        case .objcPointer(let relativeIndirectablePointerIntPair):
            return .init(relativeOffsetPlusIndirectAndInt: relativeIndirectablePointerIntPair.relativeOffsetPlusIndirectAndInt)
        case .swiftPointer(let relativeContextPointerIntPair):
            return .init(relativeOffsetPlusIndirectAndInt: relativeContextPointerIntPair.relativeOffsetPlusIndirectAndInt)
        }
    }
}

// MARK: - ReadingContext Support

extension RelativeProtocolDescriptorPointer {
    /// The protocol reference in the indirection slot that the relative
    /// pointer stored at `address` targets, marked Objective-C or Swift
    /// after this pointer's case.
    public func protocolDescriptorRef<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> ProtocolDescriptorRef {
        let storedPointer = try rawPointer.resolveIndirectType(at: address, in: context).address
        if isObjC {
            return .forObjC(storedPointer)
        } else {
            return .forSwift(storedPointer)
        }
    }

    public func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> SymbolOrElement<ProtocolDescriptorWithObjCInterop> {
        switch self {
        case .objcPointer(let relativeIndirectablePointerIntPair):
            return try relativeIndirectablePointerIntPair.resolve(at: address, in: context).map { .objc($0) }
        case .swiftPointer(let relativeContextPointerIntPair):
            return try relativeContextPointerIntPair.resolve(at: address, in: context).map { .swift($0) }
        }
    }
}
