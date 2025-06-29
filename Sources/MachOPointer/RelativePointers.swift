import MachOReading
import MachOExtensions
import MachOSymbols

public typealias RelativeOffset = Int32

public typealias RelativeDirectPointer<Pointee: Resolvable> = TargetRelativeDirectPointer<Pointee, RelativeOffset>

public typealias RelativeDirectRawPointer = TargetRelativeDirectPointer<AnyResolvable, RelativeOffset>

public typealias RelativeIndirectPointer<Pointee: Resolvable, IndirectType: RelativeIndirectType> = TargetRelativeIndirectPointer<Pointee, RelativeOffset, IndirectType> where Pointee == IndirectType.Resolved

public typealias RelativeIndirectRawPointer = TargetRelativeIndirectPointer<AnyResolvable, RelativeOffset, Pointer<AnyResolvable>>

public typealias RelativeIndirectablePointer<Pointee: Resolvable, IndirectType: RelativeIndirectType> = TargetRelativeIndirectablePointer<Pointee, RelativeOffset, IndirectType> where Pointee == IndirectType.Resolved

public typealias RelativeIndirectableRawPointer = TargetRelativeIndirectablePointer<AnyResolvable, RelativeOffset, Pointer<AnyResolvable>>

public typealias RelativeIndirectablePointerIntPair<Pointee: Resolvable, Integer: RawRepresentable, IndirectType: RelativeIndirectType> = TargetRelativeIndirectablePointerIntPair<Pointee, RelativeOffset, Integer, IndirectType> where Pointee == IndirectType.Resolved, Integer.RawValue: FixedWidthInteger

public typealias RelativeIndirectableRawPointerIntPair<Integer: RawRepresentable> = TargetRelativeIndirectablePointerIntPair<AnyResolvable, RelativeOffset, Integer, Pointer<AnyResolvable>> where Integer.RawValue: FixedWidthInteger

