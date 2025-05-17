public struct RelativeResolvableElementPointerIntPair<Context: Resolvable, Value: RawRepresentable>: RelativeIndirectablePointerIntPairProtocol where Value.RawValue: FixedWidthInteger {
    public typealias Offset = RelativeOffset
    public typealias Pointee = ResolvableElement<Context>
    public typealias IndirectType = SignedResolvableElementPointer<Context>

    public let relativeOffsetPlusIndirectAndInt: Offset
}
