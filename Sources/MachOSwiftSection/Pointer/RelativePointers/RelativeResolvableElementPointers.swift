import Foundation

public typealias RelativeMethodDescriptorPointer = RelativeResolvableElementPointer<MethodDescriptor?>

public typealias RelativeProtocolRequirementPointer = RelativeResolvableElementPointer<ProtocolRequirement?>

public typealias RelativeContextPointer<Context: Resolvable> = RelativeResolvableElementPointer<Context>

public typealias RelativeContextPointerIntPair<Context: Resolvable, Value: RawRepresentable> = RelativeResolvableElementPointerIntPair<Context, Value> where Value.RawValue: FixedWidthInteger
