import Utilities

@AssociatedValue(.public)
@CaseCheckable(.public)
public enum MethodDescriptorWrapper: Sendable {
    case method(MethodDescriptor)
    case methodOverride(MethodOverrideDescriptor)
    case methodDefaultOverride(MethodDefaultOverrideDescriptor)
}
