import Foundation

public typealias RelativeOffset = Int32

public typealias RelativeDirectPointer<Pointee: ResolvableElement> = TargetRelativeDirectPointer<Pointee, RelativeOffset>

public typealias RelativeDirectRawPointer = TargetRelativeDirectPointer<AnyResolvableElement, RelativeOffset>

public typealias RelativeIndirectPointer<Pointee: ResolvableElement, IndirectType: RelativeIndirectType> = TargetRelativeIndirectPointer<Pointee, RelativeOffset, IndirectType> where Pointee == IndirectType.Pointee

public typealias RelativeIndirectRawPointer = TargetRelativeIndirectPointer<AnyResolvableElement, RelativeOffset, Pointer<AnyResolvableElement>>

public typealias RelativeIndirectablePointer<Pointee: ResolvableElement, IndirectType: RelativeIndirectType> = TargetRelativeIndirectablePointer<Pointee, RelativeOffset, IndirectType> where Pointee == IndirectType.Pointee

public typealias RelativeIndirectableRawPointer = TargetRelativeIndirectablePointer<AnyResolvableElement, RelativeOffset, Pointer<AnyResolvableElement>>

public typealias RelativeIndirectablePointerIntPair<Pointee: ResolvableElement, Integer: FixedWidthInteger, IndirectType: RelativeIndirectType> = TargetRelativeIndirectablePointerIntPair<Pointee, RelativeOffset, Integer, IndirectType> where Pointee == IndirectType.Pointee

public typealias RelativeIndirectableRawPointerIntPair<Integer: FixedWidthInteger> = TargetRelativeIndirectablePointerIntPair<AnyResolvableElement, RelativeOffset, Integer, Pointer<AnyResolvableElement>>
