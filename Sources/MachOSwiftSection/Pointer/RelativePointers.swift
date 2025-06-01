import MachOFoundation

public typealias RelativeMethodDescriptorPointer = RelativeSymbolicElementPointer<MethodDescriptor?>

public typealias RelativeProtocolRequirementPointer = RelativeSymbolicElementPointer<ProtocolRequirement?>

public typealias RelativeContextPointer = RelativeSymbolicElementPointer<ContextDescriptorWrapper?>

public typealias RelativeContextPointerIntPair<Value: RawRepresentable> = RelativeSymbolicElementPointerIntPair<ContextDescriptorWrapper?, Value> where Value.RawValue: FixedWidthInteger
