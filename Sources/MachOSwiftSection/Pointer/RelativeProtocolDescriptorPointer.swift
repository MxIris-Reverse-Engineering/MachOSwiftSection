import MachOKit
import MachOMacro
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

    
    public func protocolDescriptorRef<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> ProtocolDescriptorRef {
        let storedPointer = try rawPointer.resolveIndirectType(from: offset, in: machO).address
        if isObjC {
            return .forObjC(storedPointer)
        } else {
            return .forSwift(storedPointer)
        }
    }

    public func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> SymbolOrElement<ProtocolDescriptorWithObjCInterop> {
        switch self {
        case .objcPointer(let relativeIndirectablePointerIntPair):
            return try relativeIndirectablePointerIntPair.resolve(from: offset, in: machO).map { .objc($0) }
        case .swiftPointer(let relativeContextPointerIntPair):
            return try relativeContextPointerIntPair.resolve(from: offset, in: machO).map { .swift($0) }
        }
    }
}
