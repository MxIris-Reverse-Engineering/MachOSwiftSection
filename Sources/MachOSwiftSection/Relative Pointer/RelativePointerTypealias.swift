import Foundation

public typealias RelativeOffset = Int32

public typealias RelativeDirectPointer<Pointee: ResolvableElement> = TargetRelativeDirectPointer<Pointee, RelativeOffset>

public typealias RelativeDirectRawPointer = TargetRelativeDirectPointer<AnyResolvableElement, RelativeOffset>

public typealias RelativeIndirectPointer<Pointee: ResolvableElement, IndirectType: RelativeIndirectType> = TargetRelativeIndirectPointer<Pointee, RelativeOffset, IndirectType> where Pointee == IndirectType.Pointee

public typealias RelativeIndirectRawPointer = TargetRelativeIndirectPointer<AnyResolvableElement, RelativeOffset, Pointer<AnyResolvableElement>>

public typealias RelativeIndirectablePointer<Pointee: ResolvableElement, IndirectType: RelativeIndirectType> = TargetRelativeIndirectablePointer<Pointee, RelativeOffset, IndirectType> where Pointee == IndirectType.Pointee

public typealias RelativeIndirectableRawPointer = TargetRelativeIndirectablePointer<AnyResolvableElement, RelativeOffset, Pointer<AnyResolvableElement>>

public typealias RelativeIndirectablePointerIntPair<Pointee: ResolvableElement, Integer: RawRepresentable, IndirectType: RelativeIndirectType> = TargetRelativeIndirectablePointerIntPair<Pointee, RelativeOffset, Integer, IndirectType> where Pointee == IndirectType.Pointee, Integer.RawValue: FixedWidthInteger

public typealias RelativeIndirectableRawPointerIntPair<Integer: RawRepresentable> = TargetRelativeIndirectablePointerIntPair<AnyResolvableElement, RelativeOffset, Integer, Pointer<AnyResolvableElement>> where Integer.RawValue: FixedWidthInteger

public typealias RelativeContextPointer<Context: ContextDescriptorProtocol> = RelativeIndirectablePointer<Context, SignedPointer<Context>>
public typealias RelativeContextPointerIntPair<Context: ContextDescriptorProtocol, Integer: RawRepresentable> = RelativeIndirectablePointerIntPair<Context, Integer, SignedPointer<Context>> where Integer.RawValue: FixedWidthInteger

public enum RelativeProtocolDescriptorPointer {
    case objcPointer(RelativeIndirectablePointerIntPair<ObjCProtocolPrefix, Bool, Pointer<ObjCProtocolPrefix>>)
    case swiftPointer(RelativeContextPointerIntPair<ProtocolDescriptor, Bool>)
}
