/// Index a sequence by a derived `ABIKey`, first element wins. Shared by the
/// two-sided differ (`threeWayMatch`) and the N-way evolution matrix so both
/// resolve a collision identically.
///
/// Known limitation: on a key collision this keeps the first element and
/// drops the rest, which can hide a removal (a breaking change classified as
/// compatible). Within one container a collision is essentially impossible —
/// legitimate overloads have distinct mangled keys, and fields / cases /
/// associated types are name-namespaced. The one realistic case is the
/// merged extension bucket: two conditional extensions (`where T: P` vs
/// `where T: Q`) each declaring a member whose mangling does not encode the
/// `where` clause collide once their members are flattened into one bucket.
/// Surfacing it properly needs a diagnostics channel on `ABIDiff` (which the
/// result type does not have today), so the drop is currently silent.
/// TODO(P2): surface colliding keys on the result instead of dropping.
/// See `Documentations/Internal/ABIDiffDesignAndLimitations.md`.
func keyedFirstWins<Element>(_ elements: [Element], by key: (Element) -> ABIKey) -> [ABIKey: Element] {
    var result: [ABIKey: Element] = [:]
    result.reserveCapacity(elements.count)
    for element in elements {
        let elementKey = key(element)
        if result[elementKey] == nil {
            result[elementKey] = element
        }
    }
    return result
}
