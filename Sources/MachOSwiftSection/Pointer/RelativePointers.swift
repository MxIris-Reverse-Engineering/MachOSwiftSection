import MachOFoundation

public typealias RelativeMethodDescriptorPointer = RelativeSymbolOrElementPointer<MethodDescriptor?>

public typealias RelativeProtocolRequirementPointer = RelativeSymbolOrElementPointer<ProtocolRequirement?>

public typealias RelativeContextPointer = RelativeSymbolOrElementPointer<ContextDescriptorWrapper?>

public typealias RelativeContextPointerIntPair<Value: RawRepresentable> = RelativeSymbolOrElementPointerIntPair<ContextDescriptorWrapper?, Value> where Value.RawValue: FixedWidthInteger
