import Foundation

/// Shared generic fixtures for tests that exercise the specialized
/// mangled-name resolution helpers in `RuntimeFunctions`.
///
/// Lives in `MachOTestingSupport` so any test target that links it gets the
/// type context descriptors compiled into the test executable's
/// `__swift5_types` section. Tests look the descriptors up by substring on
/// `MachOImage.current()` and force per-instantiation metadata emission by
/// touching `T<U>.self` before calling `Metadata.createInProcess(...)`.
///
/// Conventions:
///   - Every fixture is `package` so it stays inside the SPM package.
///   - Names are intentionally specific so substring lookups don't collide
///     with stdlib / Foundation types in the same image.
package enum SpecializedMangledNameFixtures {
    // MARK: - Structs

    package struct SingleParameterBox<A> {
        package let value: A

        package init(value: A) { self.value = value }
    }

    package struct TwoParameterPair<A, B> {
        package let first: A
        package let second: B

        package init(first: A, second: B) {
            self.first = first
            self.second = second
        }
    }

    package struct GenericArrayWrapper<A> {
        package let values: [A]
        package let count: Int

        package init(values: [A], count: Int) {
            self.values = values
            self.count = count
        }
    }

    package struct OptionalGenericFieldStruct<A> {
        package let optional: A?

        package init(optional: A?) { self.optional = optional }
    }

    package struct DictionaryGenericFieldStruct<Key: Hashable, Value> {
        package let dictionary: [Key: Value]

        package init(dictionary: [Key: Value]) { self.dictionary = dictionary }
    }

    package struct NonGenericIntStruct {
        package let count: Int

        package init(count: Int) { self.count = count }
    }

    /// Hosts a nested generic struct so the expanded-field-offset walker
    /// has to recurse with the *nested* struct's specialized metadata as
    /// the next-level substitution context. Specifically: a field of type
    /// `SingleParameterBox<A>` whose own field `value: A` ultimately
    /// resolves through the substitution chain
    /// `NestedStructHostingStruct<Int>` → `SingleParameterBox<Int>` →
    /// `value: Int`.
    package struct NestedStructHostingStruct<A> {
        package let inner: SingleParameterBox<A>
        package let trailingCount: Int

        package init(inner: SingleParameterBox<A>, trailingCount: Int) {
            self.inner = inner
            self.trailingCount = trailingCount
        }
    }

    /// Two-level struct where the *inner* struct's field is a class — the
    /// expanded-field-offset walker must NOT try to recurse into the class
    /// metadata as if it were a struct. Pre-fix, the bogus
    /// `StructMetadata.createInProcess(classMetatype)` produced a misaligned
    /// metadata, and `metadata.structDescriptor()`'s internal force-unwrap
    /// (`descriptor().struct!`) crashed on the malformed descriptor. The
    /// kind-checked construction path returns `nil` for class metatypes
    /// and skips the recursion safely.
    package struct StructHostingClassField<A> {
        package let reference: GenericContainerClass<A>
        package let trailingCount: Int

        package init(reference: GenericContainerClass<A>, trailingCount: Int) {
            self.reference = reference
            self.trailingCount = trailingCount
        }
    }

    // MARK: - Enums

    package enum GenericResultEnum<A, E: Error> {
        case success(A)
        case failure(E)
    }

    package struct FixtureError: Error {
        package init() {}
    }

    // MARK: - Classes

    /// Plain Swift class with one generic parameter. Non-resilient
    /// superclass (root) — exercises the `nonResilientImmediateMembersOffset`
    /// branch of the class resolver.
    package final class GenericContainerClass<A> {
        package let value: A

        package init(value: A) { self.value = value }
    }

    /// Two-parameter class. Pins positional ordering for the class path.
    package final class TwoParameterContainerClass<A, B> {
        package let first: A
        package let second: B

        package init(first: A, second: B) {
            self.first = first
            self.second = second
        }
    }

    /// Generic parent for `GenericSubclass`. Non-final on purpose so the
    /// subclass below has something to inherit from.
    package class GenericParentClass<A> {
        package let parentValue: A

        package init(parentValue: A) { self.parentValue = parentValue }
    }

    /// Generic subclass of a generic parent. The subclass's field descriptor
    /// lists only `childValue: B` — verifies the resolver substitutes against
    /// the innermost type's parameter ordering.
    package final class GenericSubclass<A, B>: GenericParentClass<A> {
        package let childValue: B

        package init(parentValue: A, childValue: B) {
            self.childValue = childValue
            super.init(parentValue: parentValue)
        }
    }
}
