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

// MARK: - Deprecated Mach-O and pointer forms

extension RelativeProtocolDescriptorPointer {
    @available(*, deprecated, message: "Pass a ReadingContext: protocolDescriptorRef(at: offset, in: machO.context).")
    public func protocolDescriptorRef(from offset: Int, in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ProtocolDescriptorRef {
        try protocolDescriptorRef(at: offset, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: offset, in: machO.context).")
    public func resolve(from offset: Int, in machO: some MachOSwiftSectionRepresentableWithCache) throws -> SymbolOrElement<ProtocolDescriptorWithObjCInterop> {
        try resolve(at: offset, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: protocolDescriptorRef(at: pointer, in: .inProcess).")
    public func protocolDescriptorRef(from ptr: UnsafeRawPointer) throws -> ProtocolDescriptorRef {
        try protocolDescriptorRef(at: ptr, in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: pointer, in: .inProcess).")
    public func resolve(from ptr: UnsafeRawPointer) throws -> SymbolOrElement<ProtocolDescriptorWithObjCInterop> {
        try resolve(at: ptr, in: InProcessContext.shared)
    }
}
