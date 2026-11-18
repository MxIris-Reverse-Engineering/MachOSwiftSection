/// Whether a referencing instruction calls, leaves its function, or only
/// takes an address.
public enum CodeReferenceKind: Hashable, Sendable {
    case call
    /// A branch out of the function that does not return to it.
    case tailCall
    /// A reference to a type: an instruction that takes the address of a
    /// class object, a type's metadata or its metadata accessor — a load
    /// from a GOT slot or class reference, or `adrp` / `add` of the object
    /// itself — or a call to a metadata accessor or a mangled-name
    /// instantiation, which is reported as the call it is as well.
    case reference
}
