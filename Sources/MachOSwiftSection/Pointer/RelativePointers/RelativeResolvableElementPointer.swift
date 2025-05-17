public struct RelativeResolvableElementPointer<Element: Resolvable>: RelativeIndirectablePointerProtocol {
    public typealias Offset = RelativeOffset
    public typealias Pointee = ResolvableElement<Element>
    public typealias IndirectType = SignedResolvableElementPointer<Element>

    public let relativeOffsetPlusIndirect: Offset
}
