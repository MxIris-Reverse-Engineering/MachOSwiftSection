import MachOKit
import MachOFoundation

public enum RelativeProtocolDescriptorPointer: Sendable, Equatable {
    case objcPointer(RelativeSymbolOrElementPointerIntPair<ObjCProtocolPrefix, Bool>)
    case swiftPointer(RelativeSymbolOrElementPointerIntPair<ProtocolDescriptor, Bool>)

    public var isObjC: Bool {
        switch self {
        case .objcPointer(let relativeIndirectablePointerIntPair):
            return relativeIndirectablePointerIntPair.value
        case .swiftPointer:
            return false
        }
    }

    public var rawPointer: RelativeIndirectableRawPointerIntPair<Bool> {
        switch self {
        case .objcPointer(let relativeIndirectablePointerIntPair):
            return .init(relativeOffsetPlusIndirectAndInt: relativeIndirectablePointerIntPair.relativeOffsetPlusIndirectAndInt)
        case .swiftPointer(let relativeContextPointerIntPair):
            return .init(relativeOffsetPlusIndirectAndInt: relativeContextPointerIntPair.relativeOffsetPlusIndirectAndInt)
        }
    }

    public func protocolDescriptorRef<MachO: MachOSwiftSectionRepresentableWithCache>(from offset: Int, in machO: MachO) throws -> ProtocolDescriptorRef {
        let storedPointer = try rawPointer.resolveIndirectType(from: offset, in: machO).address
        if isObjC {
            return .forObjC(storedPointer)
        } else {
            return .forSwift(storedPointer)
        }
    }

    public func resolve<MachO: MachOSwiftSectionRepresentableWithCache>(from offset: Int, in machO: MachO) throws -> SymbolOrElement<ProtocolDescriptorWithObjCInterop> {
        switch self {
        case .objcPointer(let relativeIndirectablePointerIntPair):
            return try relativeIndirectablePointerIntPair.resolve(from: offset, in: machO).map { .objc($0) }
        case .swiftPointer(let relativeContextPointerIntPair):
            return try relativeContextPointerIntPair.resolve(from: offset, in: machO).map { .swift($0) }
        }
    }

    public func protocolDescriptorRef(from ptr: UnsafeRawPointer) throws -> ProtocolDescriptorRef {
        let storedPointer = try rawPointer.resolveIndirectType(from: ptr).address
        if isObjC {
            return .forObjC(storedPointer)
        } else {
            return .forSwift(storedPointer)
        }
    }

    public func resolve(from ptr: UnsafeRawPointer) throws -> SymbolOrElement<ProtocolDescriptorWithObjCInterop> {
        switch self {
        case .objcPointer(let relativeIndirectablePointerIntPair):
            return try relativeIndirectablePointerIntPair.resolve(from: ptr).map { .objc($0) }
        case .swiftPointer(let relativeContextPointerIntPair):
            return try relativeContextPointerIntPair.resolve(from: ptr).map { .swift($0) }
        }
    }
}

// MARK: - ReadingContext Support

extension RelativeProtocolDescriptorPointer {
    public func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> SymbolOrElement<ProtocolDescriptorWithObjCInterop> {
        switch self {
        case .objcPointer(let relativeIndirectablePointerIntPair):
            return try relativeIndirectablePointerIntPair.resolve(at: address, in: context).map { .objc($0) }
        case .swiftPointer(let relativeContextPointerIntPair):
            return try relativeContextPointerIntPair.resolve(at: address, in: context).map { .swift($0) }
        }
    }
}
