import Foundation

public typealias RelativeOffset = Int32

public typealias RelativeDirectPointer<Pointee: Resolvable> = TargetRelativeDirectPointer<Pointee, RelativeOffset>

public typealias RelativeDirectRawPointer = TargetRelativeDirectPointer<AnyResolvableElement, RelativeOffset>

public typealias RelativeIndirectPointer<Pointee: Resolvable, IndirectType: RelativeIndirectType> = TargetRelativeIndirectPointer<Pointee, RelativeOffset, IndirectType> where Pointee == IndirectType.Resolved

public typealias RelativeIndirectRawPointer = TargetRelativeIndirectPointer<AnyResolvableElement, RelativeOffset, Pointer<AnyResolvableElement>>

public typealias RelativeIndirectablePointer<Pointee: Resolvable, IndirectType: RelativeIndirectType> = TargetRelativeIndirectablePointer<Pointee, RelativeOffset, IndirectType> where Pointee == IndirectType.Resolved

public typealias RelativeIndirectableRawPointer = TargetRelativeIndirectablePointer<AnyResolvableElement, RelativeOffset, Pointer<AnyResolvableElement>>

public typealias RelativeIndirectablePointerIntPair<Pointee: Resolvable, Integer: RawRepresentable, IndirectType: RelativeIndirectType> = TargetRelativeIndirectablePointerIntPair<Pointee, RelativeOffset, Integer, IndirectType> where Pointee == IndirectType.Resolved, Integer.RawValue: FixedWidthInteger

public typealias RelativeIndirectableRawPointerIntPair<Integer: RawRepresentable> = TargetRelativeIndirectablePointerIntPair<AnyResolvableElement, RelativeOffset, Integer, Pointer<AnyResolvableElement>> where Integer.RawValue: FixedWidthInteger




