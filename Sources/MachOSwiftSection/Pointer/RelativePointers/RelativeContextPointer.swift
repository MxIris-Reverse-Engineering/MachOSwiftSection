import Foundation

public struct RelativeContextPointer<Context: Resolvable>: RelativeIndirectablePointerProtocol {
    public typealias Offset = RelativeOffset
    public typealias Pointee = ResolvableElement<Context>
    public typealias IndirectType = SignedContextPointer<Context>
    
    public let relativeOffsetPlusIndirect: Offset
}

public struct RelativeContextPointerIntPair<Context: Resolvable, Value: RawRepresentable>: RelativeIndirectablePointerIntPairProtocol where Value.RawValue: FixedWidthInteger {
    public typealias Offset = RelativeOffset
    public typealias Pointee = ResolvableElement<Context>
    public typealias IndirectType = SignedContextPointer<Context>
    
    public let relativeOffsetPlusIndirectAndInt: Offset
}
