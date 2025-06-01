import MachOFoundation

public typealias RelativeMethodDescriptorPointer = RelativeResolvableElementPointer<MethodDescriptor?>

public typealias RelativeProtocolRequirementPointer = RelativeResolvableElementPointer<ProtocolRequirement?>

public typealias RelativeContextPointer<Context: Resolvable> = RelativeResolvableElementPointer<Context>

public typealias RelativeContextPointerIntPair<Context: Resolvable, Value: RawRepresentable> = RelativeResolvableElementPointerIntPair<Context, Value> where Value.RawValue: FixedWidthInteger

public typealias RelativeResolvableElementPointer<Element: Resolvable> = RelativeIndirectablePointer<ResolvableElement<Element>, SignedResolvableElementPointer<Element>>

public typealias RelativeIndirectResolvableElementPointer<Element: Resolvable> = RelativeIndirectPointer<ResolvableElement<Element>, SignedResolvableElementPointer<Element>>

public typealias RelativeResolvableElementPointerIntPair<Element: Resolvable, Value: RawRepresentable> = RelativeIndirectablePointerIntPair<ResolvableElement<Element>, Value, SignedResolvableElementPointer<Element>> where Value.RawValue: FixedWidthInteger
