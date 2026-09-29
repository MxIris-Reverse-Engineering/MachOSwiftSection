/// Index a sequence by a derived `ABIKey`, first element wins. Shared by the
/// two-sided differ (`threeWayMatch`) and the N-way evolution matrix so both
/// resolve a collision identically.
///
/// On a key collision this keeps the first element and drops the rest — which
/// could hide a removal — so the drop is **surfaced, not silent**: every
/// keying scope is independently scanned by `ABISnapshot.keyCollisions()`
/// (same first-wins rule) and the results ride on `ABIDiff.diagnostics` /
/// `ABIEvolution.keyCollisionsByVersion` and the reporters' warnings section.
/// Within one container a collision is essentially impossible — legitimate
/// overloads have distinct mangled keys, and fields / cases / associated
/// types are name-namespaced. The one realistic case is the merged extension
/// bucket: two conditional extensions (`where T: P` vs `where T: Q`) each
/// declaring a member whose mangling does not encode the `where` clause
/// collide once their members are flattened into one bucket.
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
