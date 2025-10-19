/// A data structure for managing directed substitutions, forming chains of transformations.
///
/// This map is designed to find the beginning (root original) or the end (final substitution)
/// of a substitution chain. For example, given the rules:
/// A -> B
/// B -> C
///
/// - The final substitution for A is C.
/// - The root original for C is A.
///
/// It is not based on equivalence (like a Union-Find structure) but on a directed path.
/// It includes cycle detection to prevent infinite loops.
package struct SubstitutionMap<T: Hashable> {
    // Stores the forward mapping: original -> substitution
    // e.g., [A: B] means A is substituted by B.
    private var substitutions: [T: T] = [:]

    // Stores the reverse mapping: substitution -> original
    // e.g., [B: A] means B is a substitution for A.
    private var originals: [T: T] = [:]

    package init() {}

    /// Adds a new substitution rule to the map.
    ///
    /// It establishes a directed link from the original to its substitution.
    /// A precondition ensures that a type cannot be a substitution for more than one original,
    /// maintaining a clean, non-branching reverse path.
    ///
    /// - Parameter substitution: The type that replaces the original.
    /// - Parameter original: The type to be replaced.
    package mutating func add(original: T, substitution: T) {
        // To maintain a simple chain structure, a substitution should only have one original.
        // If `originals[substitution]` is already set, it means we are trying to create a
        // structure like X -> Y and Z -> Y, which complicates finding a single "root".
        // You can remove this precondition if your model allows such branches.
        precondition(
            originals[substitution] == nil || originals[substitution] == original,
            "Substitution '\(substitution)' is already a substitute for '\(originals[substitution]!)'. It cannot also be a substitute for '\(original)'."
        )

        substitutions[original] = substitution
        originals[substitution] = original
    }

    /// Traverses the substitution chain to find the final form of a given type.
    ///
    /// For a chain A -> B -> C, the final substitution for A is C.
    /// Includes cycle detection to prevent infinite loops.
    ///
    /// - Parameter original: The starting type in the chain.
    /// - Returns: The type at the very end of the substitution chain.
    package func finalSubstitution(for original: T) -> T {
        var current = original
        var visited: Set<T> = [current]

        // Traverse forward using the `substitutions` map.
        while let next = substitutions[current] {
            // Check for a cycle. If we've seen this element before, break.
            guard visited.insert(next).inserted else {
                // Cycle detected. Return the current element to avoid infinite loop.
                print("Warning: Cycle detected at \(next). Aborting traversal.")
                break
            }
            current = next
        }
        return current
    }

    /// Traverses the substitution chain backwards to find the root original of a given type.
    ///
    /// For a chain A -> B -> C, the root original for C is A.
    /// Includes cycle detection to prevent infinite loops.
    ///
    /// - Parameter substitution: The starting type in the chain.
    /// - Returns: The type at the very beginning of the substitution chain.
    package func rootOriginal(for substitution: T) -> T {
        var current = substitution
        var visited: Set<T> = [current]

        // Traverse backward using the `originals` map.
        while let previous = originals[current] {
            // Check for a cycle.
            guard visited.insert(previous).inserted else {
                // Cycle detected.
                print("Warning: Cycle detected at \(previous). Aborting traversal.")
                break
            }
            current = previous
        }
        return current
    }
}
