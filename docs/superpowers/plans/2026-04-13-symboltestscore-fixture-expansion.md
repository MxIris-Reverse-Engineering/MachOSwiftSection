# SymbolTestsCore Fixture Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand the `SymbolTestsCore` test fixture with 44 new Swift source files and 4 edits to existing files so the MachOSwiftSection / SwiftDump / SwiftInterface parsing pipeline gets broader coverage of Swift mangling and `__swift5_*` metadata shapes.

**Architecture:** Each new file is a self-contained `public enum Feature { ... }` namespace containing `public` nested declarations that emit distinctive type context descriptors and mangled symbols. There are no modifications to parsing code or new test assertions — the deliverable is the fixture itself. Files are grouped into 19 tasks by theme: each task writes 2–4 files, rebuilds `SymbolTestsCore.framework` via `xcodebuild`, and commits. Task 19 regenerates the single snapshot baseline that depends on the fixture.

**Tech Stack:** Swift 6.2, Xcode 26, `xcodebuild`, `xcsift` (build output formatter), `swift-snapshot-testing`.

---

## File Structure

**New files (44)** in `Tests/Projects/SymbolTests/SymbolTestsCore/`:

Category 1 (general features, 24 files): `KeyPaths.swift`, `Typealiases.swift`, `Extensions.swift`, `DefaultArguments.swift`, `PropertyObservers.swift`, `Initializers.swift`, `Codable.swift`, `AccessLevels.swift`, `Availability.swift`, `DistributedActors.swift`, `StringInterpolation.swift`, `NestedGenerics.swift`, `Tuples.swift`, `FunctionTypes.swift`, `NestedFunctions.swift`, `MetatypeUsage.swift`, `ExistentialAny.swift`, `SameTypeRequirements.swift`, `OptionSetAndRawRepresentable.swift`, `DiamondInheritance.swift`, `WeakUnownedReferences.swift`, `ErrorTypes.swift`, `ResultBuilderDSL.swift`, `RethrowingFunctions.swift`.

Category 2 (extended features, 12 files): `ProtocolComposition.swift`, `OverloadedMembers.swift`, `UnsafePointers.swift`, `AsyncSequence.swift`, `PropertyWrapperVariants.swift`, `CustomLiterals.swift`, `StaticMembers.swift`, `ClassBoundGenerics.swift`, `MarkerProtocols.swift`, `DependentTypeAccess.swift`, `DeinitVariants.swift`, `CollectionConformances.swift`.

Category 3 (binary metadata variants, 8 files): `FieldDescriptorVariants.swift`, `GenericRequirementVariants.swift`, `VTableEntryVariants.swift`, `ConditionalConformanceVariants.swift`, `DefaultImplementationVariants.swift`, `FrozenResilienceContrast.swift`, `AssociatedTypeWitnessPatterns.swift`, `BuiltinTypeFields.swift`.

**Edits to existing files (4):** `Classes.swift`, `Enums.swift`, `FunctionFeatures.swift`, `Protocols.swift`.

**Snapshot regeneration:** `Tests/SwiftInterfaceTests/Snapshots/__Snapshots__/MachOFileInterfaceSnapshotTests/interfaceSnapshot.1.txt` will be regenerated in Task 19 because its content is derived from the fixture.

**No pbxproj changes** — `SymbolTestsCore` target uses `PBXFileSystemSynchronizedRootGroup`, so any `.swift` file in the folder is automatically compiled.

---

## Build Verification Command

Every task ends with this command to verify the fixture still compiles:

```bash
xcodebuild \
  -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj \
  -scheme SymbolTests \
  -configuration Release \
  -derivedDataPath Tests/Projects/SymbolTests/DerivedData \
  build 2>&1 | xcsift --quiet
```

**Expected:** exits with code 0. xcsift prints a short summary; no error output. If a file fails to compile, fix the offending source inline before committing. Do not commit a broken state.

---

## Task 1: KeyPaths, Typealiases, Extensions

**Files:**
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/KeyPaths.swift`
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/Typealiases.swift`
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/Extensions.swift`

- [ ] **Step 1: Write `KeyPaths.swift`**

```swift
import Foundation

public enum KeyPaths {
    public struct KeyPathHolderTest {
        public var readOnlyKeyPath: KeyPath<KeyPathHolderTest, Int>
        public var writableKeyPath: WritableKeyPath<KeyPathHolderTest, Int>
        public var referenceWritableKeyPath: ReferenceWritableKeyPath<KeyPathReferenceTest, String>
        public var partialKeyPath: PartialKeyPath<KeyPathHolderTest>
        public var anyKeyPath: AnyKeyPath
        public var value: Int
        public var text: String

        public init(
            readOnlyKeyPath: KeyPath<KeyPathHolderTest, Int>,
            writableKeyPath: WritableKeyPath<KeyPathHolderTest, Int>,
            referenceWritableKeyPath: ReferenceWritableKeyPath<KeyPathReferenceTest, String>,
            partialKeyPath: PartialKeyPath<KeyPathHolderTest>,
            anyKeyPath: AnyKeyPath,
            value: Int,
            text: String
        ) {
            self.readOnlyKeyPath = readOnlyKeyPath
            self.writableKeyPath = writableKeyPath
            self.referenceWritableKeyPath = referenceWritableKeyPath
            self.partialKeyPath = partialKeyPath
            self.anyKeyPath = anyKeyPath
            self.value = value
            self.text = text
        }
    }

    public class KeyPathReferenceTest {
        public var mutableText: String = ""
        public var mutableInteger: Int = 0
        public init() {}
    }

    public struct KeyPathFactoryTest<Root, Value> {
        public var keyPathProducer: (Root) -> KeyPath<Root, Value>

        public init(keyPathProducer: @escaping (Root) -> KeyPath<Root, Value>) {
            self.keyPathProducer = keyPathProducer
        }
    }
}
```

- [ ] **Step 2: Write `Typealiases.swift`**

```swift
import Foundation

public enum Typealiases {
    public typealias IntegerAlias = Int
    public typealias CompletionHandler = (Int, Error?) -> Void
    public typealias ResultHandler<Value> = (Result<Value, Error>) -> Void
    public typealias EquatablePair<Element: Equatable> = (left: Element, right: Element)

    public struct TypealiasContainerTest<Element> {
        public typealias NestedAlias = Element
        public typealias NestedCollection = Array<Element>
        public typealias NestedHandler = (Element) -> Void

        public var element: NestedAlias
        public var collection: NestedCollection
        public var handler: NestedHandler

        public init(element: NestedAlias, collection: NestedCollection, handler: @escaping NestedHandler) {
            self.element = element
            self.collection = collection
            self.handler = handler
        }
    }

    public struct ConstrainedTypealiasTest<Element> where Element: Comparable {
        public typealias ConstrainedRange = ClosedRange<Element>
        public var range: ConstrainedRange

        public init(range: ConstrainedRange) {
            self.range = range
        }
    }
}
```

- [ ] **Step 3: Write `Extensions.swift`**

```swift
import Foundation

public enum Extensions {
    public struct ExtensionBaseStruct<Element> {
        public var element: Element
        public init(element: Element) {
            self.element = element
        }
    }

    public struct ExtensionConstrainedStruct<Element> {
        public var element: Element
        public init(element: Element) {
            self.element = element
        }
    }

    public protocol ExtensionProtocol {
        associatedtype Item
        var item: Item { get }
    }
}

extension Extensions.ExtensionBaseStruct where Element: Equatable {
    public func isEqualTo(_ other: Self) -> Bool {
        element == other.element
    }
}

extension Extensions.ExtensionBaseStruct where Element: Comparable {
    public func isLessThan(_ other: Self) -> Bool {
        element < other.element
    }
}

extension Extensions.ExtensionBaseStruct where Element: Hashable & Sendable {
    public func computeHash() -> Int {
        element.hashValue
    }
}

extension Extensions.ExtensionConstrainedStruct: Extensions.ExtensionProtocol where Element: Hashable {
    public var item: Element { element }
}

extension Extensions.ExtensionProtocol where Item: Equatable {
    public func matches(_ other: Item) -> Bool {
        item == other
    }
}

extension Extensions.ExtensionProtocol where Item: Comparable {
    public func isLessThan(_ other: Item) -> Bool {
        item < other
    }
}
```

- [ ] **Step 4: Build fixture to verify**

Run the Build Verification Command from the top of this plan.
Expected: xcodebuild exits 0 with no errors reported by xcsift.

- [ ] **Step 5: Commit**

```bash
git add Tests/Projects/SymbolTests/SymbolTestsCore/KeyPaths.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/Typealiases.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/Extensions.swift
git commit -m "test(fixture): add KeyPaths, Typealiases, Extensions"
```

---

## Task 2: DefaultArguments, PropertyObservers

**Files:**
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/DefaultArguments.swift`
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/PropertyObservers.swift`

- [ ] **Step 1: Write `DefaultArguments.swift`**

```swift
import Foundation

public enum DefaultArguments {
    public struct DefaultArgumentMethodTest {
        public func greet(name: String = "World", repeated: Int = 1, punctuation: Character = "!") -> String {
            String(repeating: "\(name)\(punctuation) ", count: repeated)
        }

        public func append(_ value: Int, to collection: [Int] = []) -> [Int] {
            collection + [value]
        }

        public static func createDefault(label: String = "default", value: Int = 0) -> DefaultArgumentMethodTest {
            DefaultArgumentMethodTest()
        }
    }

    public struct DefaultArgumentInitializerTest {
        public var name: String
        public var count: Int
        public var enabled: Bool

        public init(name: String = "default", count: Int = 0, enabled: Bool = true) {
            self.name = name
            self.count = count
            self.enabled = enabled
        }
    }

    public struct DefaultArgumentSubscriptTest {
        public subscript(index: Int = 0, fallback fallback: String = "") -> String {
            fallback
        }
    }

    public class DefaultArgumentClassTest {
        public func process(value: Int = 42, multiplier: Double = 1.0) -> Double {
            Double(value) * multiplier
        }

        public init(initial: Int = 0, scale: Double = 1.0) {}
    }
}
```

- [ ] **Step 2: Write `PropertyObservers.swift`**

```swift
import Foundation

public enum PropertyObservers {
    public class PropertyObserverClassTest {
        public var observedValue: Int = 0 {
            willSet {
                print("willSet: \(newValue)")
            }
            didSet {
                print("didSet: \(oldValue)")
            }
        }

        public var observedName: String = "" {
            willSet(newName) {
                _ = newName
            }
            didSet(oldName) {
                _ = oldName
            }
        }

        public var computedBacking: Int {
            get { observedValue }
            set { observedValue = newValue }
        }

        public init() {}
    }

    public struct PropertyObserverStructTest {
        public var observedField: Double = 0.0 {
            willSet {
                _ = newValue
            }
            didSet {
                _ = oldValue
            }
        }

        public init() {}
    }
}
```

- [ ] **Step 3: Build fixture**

Run the Build Verification Command.
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Tests/Projects/SymbolTests/SymbolTestsCore/DefaultArguments.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/PropertyObservers.swift
git commit -m "test(fixture): add DefaultArguments and PropertyObservers"
```

---

## Task 3: Initializers, Codable

**Files:**
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/Initializers.swift`
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/Codable.swift`

- [ ] **Step 1: Write `Initializers.swift`**

```swift
import Foundation

public enum Initializers {
    public struct CustomInitializerError: Error {
        public let reason: String
        public init(reason: String) {
            self.reason = reason
        }
    }

    public class ConvenienceInitializerTest {
        public let primaryValue: Int
        public let secondaryValue: String

        public init(primaryValue: Int, secondaryValue: String) {
            self.primaryValue = primaryValue
            self.secondaryValue = secondaryValue
        }

        public convenience init(primaryValue: Int) {
            self.init(primaryValue: primaryValue, secondaryValue: "")
        }

        public convenience init() {
            self.init(primaryValue: 0, secondaryValue: "")
        }
    }

    public class RequiredInitializerTest {
        public let value: Int

        public required init(value: Int) {
            self.value = value
        }

        public required convenience init() {
            self.init(value: 0)
        }
    }

    public class RequiredInitializerSubclass: RequiredInitializerTest {
        public let extraValue: String

        public required init(value: Int) {
            self.extraValue = ""
            super.init(value: value)
        }

        public required convenience init() {
            self.init(value: 0)
        }
    }

    public struct FailableInitializerTest {
        public let value: Int

        public init?(value: Int) {
            guard value >= 0 else { return nil }
            self.value = value
        }

        public init!(unsafe value: Int) {
            self.value = value
        }
    }

    public struct TypedThrowingInitializerTest {
        public let value: Int

        public init(value: Int) throws(CustomInitializerError) {
            guard value >= 0 else {
                throw CustomInitializerError(reason: "negative")
            }
            self.value = value
        }
    }

    public actor AsyncInitializerActorTest {
        public let identifier: Int

        public init(identifier: Int) async {
            self.identifier = identifier
        }
    }
}
```

- [ ] **Step 2: Write `Codable.swift`**

```swift
import Foundation

public enum CodableTests {
    public struct SynthesizedCodableTest: Codable {
        public var identifier: Int
        public var name: String
        public var optionalValue: Double?

        public init(identifier: Int, name: String, optionalValue: Double?) {
            self.identifier = identifier
            self.name = name
            self.optionalValue = optionalValue
        }
    }

    public struct CustomCodableTest: Codable {
        public var displayName: String
        public var hiddenCount: Int

        private enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case hiddenCount = "count"
        }

        public init(displayName: String, hiddenCount: Int) {
            self.displayName = displayName
            self.hiddenCount = hiddenCount
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.displayName = try container.decode(String.self, forKey: .displayName)
            self.hiddenCount = try container.decode(Int.self, forKey: .hiddenCount)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(displayName, forKey: .displayName)
            try container.encode(hiddenCount, forKey: .hiddenCount)
        }
    }

    public class CodableClassTest: Codable {
        public var identifier: Int
        public var label: String

        public init(identifier: Int, label: String) {
            self.identifier = identifier
            self.label = label
        }
    }

    public enum CodableEnumTest: Codable {
        case empty
        case withValue(Int)
        case withPair(left: String, right: Int)
    }

    public struct GenericCodableTest<Element: Codable>: Codable {
        public var element: Element
        public var metadata: [String: String]

        public init(element: Element, metadata: [String: String]) {
            self.element = element
            self.metadata = metadata
        }
    }
}
```

- [ ] **Step 3: Build fixture**

Run the Build Verification Command. Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Tests/Projects/SymbolTests/SymbolTestsCore/Initializers.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/Codable.swift
git commit -m "test(fixture): add Initializers and Codable"
```

---

## Task 4: AccessLevels, Availability

**Files:**
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/AccessLevels.swift`
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/Availability.swift`

- [ ] **Step 1: Write `AccessLevels.swift`**

```swift
import Foundation

public enum AccessLevels {
    public struct PublicAccessLevelTest {
        public var publicField: Int
        package var packageField: Int
        internal var internalField: Int
        fileprivate var fileprivateField: Int
        private var privateField: Int

        public init(publicField: Int, packageField: Int, internalField: Int, fileprivateField: Int, privateField: Int) {
            self.publicField = publicField
            self.packageField = packageField
            self.internalField = internalField
            self.fileprivateField = fileprivateField
            self.privateField = privateField
        }

        public func publicMethod() {}
        package func packageMethod() {}
        internal func internalMethod() {}
        fileprivate func fileprivateMethod() {}
        private func privateMethod() {}
    }

    open class OpenAccessLevelTest {
        open var openField: Int = 0
        public var publicField: Int = 0

        open func openMethod() {}
        public func publicMethod() {}

        public init() {}
    }

    public class SubclassOfOpenAccessLevel: OpenAccessLevelTest {
        open override func openMethod() {}
        public override var openField: Int {
            get { 0 }
            set {}
        }
    }
}
```

- [ ] **Step 2: Write `Availability.swift`**

```swift
import Foundation

public enum Availability {
    @available(macOS 12.0, iOS 15.0, *)
    public struct MultiPlatformAvailableTest {
        public var value: Int
        public init(value: Int) {
            self.value = value
        }
    }

    @available(macOS, deprecated: 13.0, message: "Use RenamedAvailabilityNewTest instead")
    public struct DeprecatedAvailabilityTest {
        public var value: Int
        public init(value: Int) {
            self.value = value
        }
    }

    public struct RenamedAvailabilityNewTest {
        public init() {}
    }

    @available(macOS, introduced: 10.15, deprecated: 14.0, obsoleted: 15.0, message: "Obsoleted in macOS 15")
    public struct ObsoletedAvailabilityTest {
        public init() {}
    }

    public struct AvailabilityMemberTest {
        @available(macOS 13.0, *)
        public var modernField: Int {
            0
        }

        @available(macOS, deprecated: 13.0)
        public func deprecatedMethod() {}

        @available(*, unavailable, message: "No longer supported")
        public func unavailableMethod() {}

        public init() {}
    }
}
```

- [ ] **Step 3: Build fixture**

Run the Build Verification Command. Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Tests/Projects/SymbolTests/SymbolTestsCore/AccessLevels.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/Availability.swift
git commit -m "test(fixture): add AccessLevels and Availability"
```

---

## Task 5: DistributedActors, StringInterpolation

**Files:**
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/DistributedActors.swift`
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/StringInterpolation.swift`

- [ ] **Step 1: Write `DistributedActors.swift`**

```swift
import Foundation
import Distributed

public enum DistributedActors {
    public distributed actor DistributedActorTest {
        public typealias ActorSystem = LocalTestingDistributedActorSystem

        public distributed func remoteMethod(value: Int) -> Int {
            value * 2
        }

        public distributed func remoteThrowingMethod() throws -> String {
            "result"
        }

        public nonisolated var nonisolatedProperty: String {
            "nonisolated"
        }

        public distributed func parameterizedMethod(label: String, count: Int) -> String {
            String(repeating: label, count: count)
        }
    }

    public distributed actor GenericDistributedActorTest<Element: Codable & Sendable> {
        public typealias ActorSystem = LocalTestingDistributedActorSystem

        public distributed func process(element: Element) -> Element {
            element
        }
    }
}
```

- [ ] **Step 2: Write `StringInterpolation.swift`**

```swift
import Foundation

public enum StringInterpolations {
    public struct CustomStringInterpolationTest: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
        public var storage: String

        public init(stringLiteral value: String) {
            self.storage = value
        }

        public init(stringInterpolation: StringInterpolation) {
            self.storage = stringInterpolation.accumulator
        }

        public struct StringInterpolation: StringInterpolationProtocol {
            public var accumulator: String

            public init(literalCapacity: Int, interpolationCount: Int) {
                self.accumulator = ""
                self.accumulator.reserveCapacity(literalCapacity + interpolationCount)
            }

            public mutating func appendLiteral(_ literal: String) {
                accumulator.append(literal)
            }

            public mutating func appendInterpolation(_ value: Int) {
                accumulator.append(String(value))
            }

            public mutating func appendInterpolation(_ value: String) {
                accumulator.append(value)
            }

            public mutating func appendInterpolation<Value: CustomStringConvertible>(_ value: Value) {
                accumulator.append(value.description)
            }

            public mutating func appendInterpolation(formatted value: Double, precision: Int) {
                accumulator.append(String(format: "%.\(precision)f", value))
            }
        }
    }
}
```

- [ ] **Step 3: Build fixture**

Run the Build Verification Command.
Expected: build succeeds. If `LocalTestingDistributedActorSystem` is unavailable, replace with a minimal custom `DistributedActorSystem` conformance (follow compiler diagnostics).

- [ ] **Step 4: Commit**

```bash
git add Tests/Projects/SymbolTests/SymbolTestsCore/DistributedActors.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/StringInterpolation.swift
git commit -m "test(fixture): add DistributedActors and StringInterpolation"
```

---

## Task 6: NestedGenerics, Tuples, FunctionTypes

**Files:**
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/NestedGenerics.swift`
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/Tuples.swift`
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/FunctionTypes.swift`

- [ ] **Step 1: Write `NestedGenerics.swift`**

```swift
import Foundation

public enum NestedGenerics {
    public struct OuterGenericTest<Outer> {
        public struct InnerGenericTest<Inner> {
            public struct InnerMostGenericTest<InnerMost> {
                public var outer: Outer
                public var inner: Inner
                public var innerMost: InnerMost

                public init(outer: Outer, inner: Inner, innerMost: InnerMost) {
                    self.outer = outer
                    self.inner = inner
                    self.innerMost = innerMost
                }
            }
        }
    }

    public struct NestedGenericWithConstraintsTest<Outer: Comparable> {
        public struct InnerConstrainedTest<Inner: Hashable> where Outer: Sendable {
            public var outer: Outer
            public var inner: Inner

            public init(outer: Outer, inner: Inner) {
                self.outer = outer
                self.inner = inner
            }
        }
    }

    public struct NestedTypealiasGenericTest<Element> {
        public typealias ElementArray = [Element]
        public typealias ElementDictionary<Key: Hashable> = [Key: Element]

        public var elements: ElementArray

        public init(elements: ElementArray) {
            self.elements = elements
        }
    }
}
```

- [ ] **Step 2: Write `Tuples.swift`**

```swift
import Foundation

public enum Tuples {
    public struct TupleFieldTest {
        public var namedTuple: (first: Int, second: String)
        public var unnamedTuple: (Int, Double, Bool)
        public var nestedTuple: ((Int, Int), (String, String))

        public init(
            namedTuple: (first: Int, second: String),
            unnamedTuple: (Int, Double, Bool),
            nestedTuple: ((Int, Int), (String, String))
        ) {
            self.namedTuple = namedTuple
            self.unnamedTuple = unnamedTuple
            self.nestedTuple = nestedTuple
        }
    }

    public struct TupleFunctionTest {
        public func acceptTuple(_ value: (Int, String)) -> (Bool, Double) {
            (true, 0.0)
        }

        public func acceptNamedTuple(_ value: (identifier: Int, label: String)) -> (result: Bool, score: Double) {
            (result: true, score: 0.0)
        }

        public func returnLargeTuple() -> (Int, Double, String, Bool, Int, Double) {
            (0, 0.0, "", true, 0, 0.0)
        }
    }

    public struct GenericTupleTest<First, Second> {
        public var pair: (First, Second)
        public var labeled: (left: First, right: Second)

        public init(pair: (First, Second), labeled: (left: First, right: Second)) {
            self.pair = pair
            self.labeled = labeled
        }
    }
}
```

- [ ] **Step 3: Write `FunctionTypes.swift`**

```swift
import Foundation

public enum FunctionTypes {
    public struct FunctionFieldTest {
        public var simpleFunction: (Int) -> Int
        public var multiArgumentFunction: (Int, String, Bool) -> Double
        public var throwingFunction: () throws -> Int
        public var asyncFunction: () async -> String
        public var asyncThrowingFunction: () async throws -> Int

        public init(
            simpleFunction: @escaping (Int) -> Int,
            multiArgumentFunction: @escaping (Int, String, Bool) -> Double,
            throwingFunction: @escaping () throws -> Int,
            asyncFunction: @escaping () async -> String,
            asyncThrowingFunction: @escaping () async throws -> Int
        ) {
            self.simpleFunction = simpleFunction
            self.multiArgumentFunction = multiArgumentFunction
            self.throwingFunction = throwingFunction
            self.asyncFunction = asyncFunction
            self.asyncThrowingFunction = asyncThrowingFunction
        }
    }

    public struct HigherOrderFunctionTest {
        public func acceptFunctionReturningFunction(_ producer: @escaping (Int) -> (Double) -> String) -> String {
            producer(0)(0.0)
        }

        public func returnFunctionReturningFunction() -> (Int) -> (Double) -> String {
            { _ in { _ in "" } }
        }

        public func curriedFunction(_ firstArgument: Int) -> (Double) -> (String) -> Bool {
            { _ in { _ in false } }
        }
    }

    public struct FunctionTypealiasTest {
        public typealias Transformer<Input, Output> = (Input) -> Output
        public typealias Predicate<Value> = (Value) -> Bool
        public typealias BiFunction<First, Second, Result> = (First, Second) -> Result

        public var transformer: Transformer<Int, String>
        public var predicate: Predicate<Int>
        public var biFunction: BiFunction<Int, String, Bool>

        public init(
            transformer: @escaping Transformer<Int, String>,
            predicate: @escaping Predicate<Int>,
            biFunction: @escaping BiFunction<Int, String, Bool>
        ) {
            self.transformer = transformer
            self.predicate = predicate
            self.biFunction = biFunction
        }
    }
}
```

- [ ] **Step 4: Build fixture**

Run the Build Verification Command. Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Tests/Projects/SymbolTests/SymbolTestsCore/NestedGenerics.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/Tuples.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/FunctionTypes.swift
git commit -m "test(fixture): add NestedGenerics, Tuples, FunctionTypes"
```

---

## Task 7: NestedFunctions, MetatypeUsage, ExistentialAny

**Files:**
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/NestedFunctions.swift`
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/MetatypeUsage.swift`
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/ExistentialAny.swift`

- [ ] **Step 1: Write `NestedFunctions.swift`**

```swift
import Foundation

public enum NestedFunctions {
    public struct NestedFunctionHolderTest {
        public func outerFunction(parameter: Int) -> Int {
            func innerFunction(inner: Int) -> Int {
                inner * 2
            }

            func secondInnerFunction(first: Int, second: Int) -> Int {
                first + second
            }

            return innerFunction(inner: parameter) + secondInnerFunction(first: parameter, second: parameter)
        }

        public func outerGenericFunction<Element>(element: Element) -> [Element] {
            func innerGenericFunction<Item>(item: Item) -> [Item] {
                [item, item]
            }

            return innerGenericFunction(item: element)
        }

        public func outerWithLocalType() -> Int {
            struct LocalStruct {
                var value: Int
            }

            let local = LocalStruct(value: 42)
            return local.value
        }

        public func outerWithLocalClass() -> String {
            class LocalClass {
                var label: String = ""
            }

            let instance = LocalClass()
            return instance.label
        }
    }
}
```

- [ ] **Step 2: Write `MetatypeUsage.swift`**

```swift
import Foundation

public enum MetatypeUsage {
    public struct MetatypeFieldTest {
        public var concreteMetatype: Int.Type
        public var anyMetatype: Any.Type
        public var protocolMetatype: any Protocols.ProtocolTest.Type
        public var anyObjectMetatype: AnyObject.Type

        public init(
            concreteMetatype: Int.Type,
            anyMetatype: Any.Type,
            protocolMetatype: any Protocols.ProtocolTest.Type,
            anyObjectMetatype: AnyObject.Type
        ) {
            self.concreteMetatype = concreteMetatype
            self.anyMetatype = anyMetatype
            self.protocolMetatype = protocolMetatype
            self.anyObjectMetatype = anyObjectMetatype
        }
    }

    public struct MetatypeFunctionTest {
        public func acceptMetatype<Element>(_ type: Element.Type) -> Element.Type {
            type
        }

        public func acceptProtocolMetatype(_ type: any Protocols.ProtocolTest.Type) -> String {
            String(describing: type)
        }

        public func returnMetatype() -> Self.Type {
            Self.self
        }

        public func dynamicType<Element>(of value: Element) -> Element.Type {
            type(of: value)
        }
    }
}
```

- [ ] **Step 3: Write `ExistentialAny.swift`**

```swift
import Foundation

public enum ExistentialAny {
    public struct ExistentialFieldTest {
        public var simpleExistential: any Protocols.ProtocolTest
        public var compositionExistential: any Protocols.ProtocolTest & Sendable
        public var optionalExistential: (any Protocols.ProtocolTest)?
        public var existentialArray: [any Protocols.ProtocolTest]
        public var existentialDictionary: [String: any Protocols.ProtocolTest]
        public var existentialFunction: (any Protocols.ProtocolTest) -> Void

        public init(
            simpleExistential: any Protocols.ProtocolTest,
            compositionExistential: any Protocols.ProtocolTest & Sendable,
            optionalExistential: (any Protocols.ProtocolTest)?,
            existentialArray: [any Protocols.ProtocolTest],
            existentialDictionary: [String: any Protocols.ProtocolTest],
            existentialFunction: @escaping (any Protocols.ProtocolTest) -> Void
        ) {
            self.simpleExistential = simpleExistential
            self.compositionExistential = compositionExistential
            self.optionalExistential = optionalExistential
            self.existentialArray = existentialArray
            self.existentialDictionary = existentialDictionary
            self.existentialFunction = existentialFunction
        }
    }

    public struct ExistentialClassBoundTest {
        public var classBound: any Protocols.ClassBoundProtocolTest
        public var anyObjectReference: AnyObject

        public init(classBound: any Protocols.ClassBoundProtocolTest, anyObjectReference: AnyObject) {
            self.classBound = classBound
            self.anyObjectReference = anyObjectReference
        }
    }
}
```

- [ ] **Step 4: Build fixture**

Run the Build Verification Command. Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Tests/Projects/SymbolTests/SymbolTestsCore/NestedFunctions.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/MetatypeUsage.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/ExistentialAny.swift
git commit -m "test(fixture): add NestedFunctions, MetatypeUsage, ExistentialAny"
```

---

## Task 8: SameTypeRequirements, OptionSetAndRawRepresentable, DiamondInheritance

**Files:**
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/SameTypeRequirements.swift`
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/OptionSetAndRawRepresentable.swift`
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/DiamondInheritance.swift`

- [ ] **Step 1: Write `SameTypeRequirements.swift`**

```swift
import Foundation

public enum SameTypeRequirements {
    public struct SameTypeElementTest<First: Sequence, Second: Sequence> where First.Element == Second.Element {
        public var first: First
        public var second: Second

        public init(first: First, second: Second) {
            self.first = first
            self.second = second
        }
    }

    public struct NestedSameTypeTest<
        First: Collection,
        Second: Collection
    > where First.Element == Second.Element, First.Index == Int, Second.Index == Int {
        public var first: First
        public var second: Second

        public init(first: First, second: Second) {
            self.first = first
            self.second = second
        }
    }

    public struct ChainedSameTypeTest<
        First: Protocols.ProtocolTest,
        Second: Protocols.ProtocolTest,
        Third: Protocols.ProtocolTest
    > where First.Body == Second, Second.Body == Third {
        public var first: First
        public var second: Second
        public var third: Third

        public init(first: First, second: Second, third: Third) {
            self.first = first
            self.second = second
            self.third = third
        }
    }
}
```

- [ ] **Step 2: Write `OptionSetAndRawRepresentable.swift`**

```swift
import Foundation

public enum OptionSetAndRawRepresentable {
    public struct OptionSetTest: OptionSet {
        public let rawValue: UInt

        public init(rawValue: UInt) {
            self.rawValue = rawValue
        }

        public static let first = OptionSetTest(rawValue: 1 << 0)
        public static let second = OptionSetTest(rawValue: 1 << 1)
        public static let third = OptionSetTest(rawValue: 1 << 2)
        public static let all: OptionSetTest = [.first, .second, .third]
    }

    public struct StringRawRepresentableTest: RawRepresentable {
        public let rawValue: String

        public init?(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    public struct IntRawRepresentableTest: RawRepresentable {
        public var rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }

    public struct GenericRawRepresentableTest<Raw: Hashable>: RawRepresentable {
        public var rawValue: Raw

        public init(rawValue: Raw) {
            self.rawValue = rawValue
        }
    }
}
```

- [ ] **Step 3: Write `DiamondInheritance.swift`**

```swift
import Foundation

public enum DiamondInheritance {
    public protocol DiamondBaseProtocol {
        func baseMethod() -> String
    }

    public protocol DiamondLeftProtocol: DiamondBaseProtocol {
        func leftMethod() -> Int
    }

    public protocol DiamondRightProtocol: DiamondBaseProtocol {
        func rightMethod() -> Double
    }

    public protocol DiamondBottomProtocol: DiamondLeftProtocol, DiamondRightProtocol {
        func bottomMethod() -> Bool
    }

    public struct DiamondImplementationTest: DiamondBottomProtocol {
        public func baseMethod() -> String { "" }
        public func leftMethod() -> Int { 0 }
        public func rightMethod() -> Double { 0.0 }
        public func bottomMethod() -> Bool { false }

        public init() {}
    }

    public protocol TriDiamondRootProtocol {
        func root() -> String
    }

    public protocol TriDiamondFirstProtocol: TriDiamondRootProtocol {
        func first() -> Int
    }

    public protocol TriDiamondSecondProtocol: TriDiamondRootProtocol {
        func second() -> Int
    }

    public protocol TriDiamondThirdProtocol: TriDiamondRootProtocol {
        func third() -> Int
    }

    public protocol TriDiamondLeafProtocol: TriDiamondFirstProtocol, TriDiamondSecondProtocol, TriDiamondThirdProtocol {
        func leaf() -> Int
    }
}
```

- [ ] **Step 4: Build fixture**

Run the Build Verification Command. Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Tests/Projects/SymbolTests/SymbolTestsCore/SameTypeRequirements.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/OptionSetAndRawRepresentable.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/DiamondInheritance.swift
git commit -m "test(fixture): add SameTypeRequirements, OptionSet/RawRepresentable, DiamondInheritance"
```

---

## Task 9: WeakUnownedReferences, ErrorTypes, ResultBuilderDSL, RethrowingFunctions

**Files:**
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/WeakUnownedReferences.swift`
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/ErrorTypes.swift`
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/ResultBuilderDSL.swift`
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/RethrowingFunctions.swift`

- [ ] **Step 1: Write `WeakUnownedReferences.swift`**

```swift
import Foundation

public enum WeakUnownedReferences {
    public class ReferenceTargetTest {
        public var value: Int = 0
        public init() {}
    }

    public class WeakReferenceHolderTest {
        public weak var weakReference: ReferenceTargetTest?
        public weak var weakAnyObject: AnyObject?
        public init() {}
    }

    public class UnownedReferenceHolderTest {
        public unowned var unownedReference: ReferenceTargetTest
        public unowned(safe) var unownedSafeReference: ReferenceTargetTest
        public unowned(unsafe) var unownedUnsafeReference: ReferenceTargetTest

        public init(target: ReferenceTargetTest) {
            self.unownedReference = target
            self.unownedSafeReference = target
            self.unownedUnsafeReference = target
        }
    }

    public class MixedReferenceHolderTest {
        public weak var weakReference: ReferenceTargetTest?
        public unowned var unownedReference: ReferenceTargetTest
        public var strongReference: ReferenceTargetTest

        public init(target: ReferenceTargetTest) {
            self.unownedReference = target
            self.strongReference = target
        }
    }
}
```

- [ ] **Step 2: Write `ErrorTypes.swift`**

```swift
import Foundation

public enum ErrorTypes {
    public enum SimpleErrorTest: Error {
        case notFound
        case invalid
        case unknown
    }

    public enum AssociatedValueErrorTest: Error {
        case withMessage(String)
        case withCode(Int)
        case withContext(message: String, code: Int, underlying: (any Error)?)
    }

    public struct LocalizedErrorTest: LocalizedError {
        public let errorDescription: String?
        public let failureReason: String?
        public let recoverySuggestion: String?
        public let helpAnchor: String?

        public init(description: String, reason: String, suggestion: String, helpAnchor: String) {
            self.errorDescription = description
            self.failureReason = reason
            self.recoverySuggestion = suggestion
            self.helpAnchor = helpAnchor
        }
    }

    public struct CustomNSErrorTest: CustomNSError {
        public static let errorDomain: String = "com.test.CustomNSErrorTest"
        public let errorCode: Int
        public let errorUserInfo: [String: Any]

        public init(errorCode: Int, errorUserInfo: [String: Any]) {
            self.errorCode = errorCode
            self.errorUserInfo = errorUserInfo
        }
    }

    public struct SendableErrorTest: Error, Sendable {
        public let identifier: Int
        public let descriptionText: String

        public init(identifier: Int, descriptionText: String) {
            self.identifier = identifier
            self.descriptionText = descriptionText
        }
    }
}
```

- [ ] **Step 3: Write `ResultBuilderDSL.swift`**

```swift
import Foundation

public enum ResultBuilderDSL {
    @resultBuilder
    public struct FullResultBuilderTest {
        public static func buildExpression(_ expression: Int) -> [Int] {
            [expression]
        }

        public static func buildExpression(_ expression: [Int]) -> [Int] {
            expression
        }

        public static func buildBlock(_ components: [Int]...) -> [Int] {
            components.flatMap { $0 }
        }

        public static func buildOptional(_ component: [Int]?) -> [Int] {
            component ?? []
        }

        public static func buildEither(first component: [Int]) -> [Int] {
            component
        }

        public static func buildEither(second component: [Int]) -> [Int] {
            component
        }

        public static func buildArray(_ components: [[Int]]) -> [Int] {
            components.flatMap { $0 }
        }

        public static func buildLimitedAvailability(_ component: [Int]) -> [Int] {
            component
        }

        public static func buildFinalResult(_ component: [Int]) -> [Int] {
            component
        }
    }

    @resultBuilder
    public struct GenericResultBuilderTest<Element> {
        public static func buildBlock(_ components: [Element]...) -> [Element] {
            components.flatMap { $0 }
        }

        public static func buildExpression(_ expression: Element) -> [Element] {
            [expression]
        }

        public static func buildOptional(_ component: [Element]?) -> [Element] {
            component ?? []
        }
    }
}
```

- [ ] **Step 4: Write `RethrowingFunctions.swift`**

```swift
import Foundation

public enum RethrowingFunctions {
    public struct RethrowingHolderTest {
        public func rethrowing(_ body: () throws -> Int) rethrows -> Int {
            try body()
        }

        public func asyncRethrowing(_ body: () async throws -> Int) async rethrows -> Int {
            try await body()
        }

        public func rethrowingMap<Element>(_ elements: [Element], transform: (Element) throws -> Int) rethrows -> [Int] {
            try elements.map(transform)
        }

        public func rethrowingWithDefault(_ body: () throws -> Int, defaultValue: Int = 0) rethrows -> Int {
            try body()
        }

        public func rethrowingGeneric<Input, Output>(_ input: Input, transform: (Input) throws -> Output) rethrows -> Output {
            try transform(input)
        }
    }
}
```

- [ ] **Step 5: Build fixture**

Run the Build Verification Command. Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Tests/Projects/SymbolTests/SymbolTestsCore/WeakUnownedReferences.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/ErrorTypes.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/ResultBuilderDSL.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/RethrowingFunctions.swift
git commit -m "test(fixture): add WeakUnowned, ErrorTypes, ResultBuilderDSL, Rethrowing"
```

---

## Task 10: ProtocolComposition, OverloadedMembers, UnsafePointers

**Files:**
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/ProtocolComposition.swift`
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/OverloadedMembers.swift`
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/UnsafePointers.swift`

- [ ] **Step 1: Write `ProtocolComposition.swift`**

```swift
import Foundation

public enum ProtocolComposition {
    public protocol ComposeFirstProtocol {
        func first() -> Int
    }

    public protocol ComposeSecondProtocol {
        func second() -> String
    }

    public protocol ComposeThirdProtocol {
        func third() -> Double
    }

    public struct ProtocolCompositionFieldTest {
        public var twoComposition: any ComposeFirstProtocol & ComposeSecondProtocol
        public var threeComposition: any ComposeFirstProtocol & ComposeSecondProtocol & ComposeThirdProtocol
        public var classBoundComposition: any AnyObject & ComposeFirstProtocol
        public var sendableComposition: any Sendable & ComposeFirstProtocol

        public init(
            twoComposition: any ComposeFirstProtocol & ComposeSecondProtocol,
            threeComposition: any ComposeFirstProtocol & ComposeSecondProtocol & ComposeThirdProtocol,
            classBoundComposition: any AnyObject & ComposeFirstProtocol,
            sendableComposition: any Sendable & ComposeFirstProtocol
        ) {
            self.twoComposition = twoComposition
            self.threeComposition = threeComposition
            self.classBoundComposition = classBoundComposition
            self.sendableComposition = sendableComposition
        }
    }

    public struct ProtocolCompositionFunctionTest {
        public func acceptComposition(_ value: any ComposeFirstProtocol & ComposeSecondProtocol) {}

        public func returnComposition() -> any ComposeFirstProtocol & ComposeSecondProtocol {
            fatalError()
        }

        public func genericCompositionParameter<Element: ComposeFirstProtocol & ComposeSecondProtocol>(_ element: Element) {}
    }
}
```

- [ ] **Step 2: Write `OverloadedMembers.swift`**

```swift
import Foundation

public enum OverloadedMembers {
    public struct OverloadedMethodTest {
        public func process(_ value: Int) -> Int { value }
        public func process(_ value: Double) -> Double { value }
        public func process(_ value: String) -> String { value }
        public func process(_ first: Int, _ second: Int) -> Int { first + second }
        public func process(_ first: Int, label: String) -> String { label }
        public func process<Element>(_ value: Element) -> Element { value }
        public func process<Element: Equatable>(equatable value: Element) -> Bool { false }
    }

    public struct OverloadedSubscriptTest {
        public subscript(index: Int) -> Int { 0 }
        public subscript(key: String) -> String { "" }
        public subscript(range: Range<Int>) -> [Int] { [] }
        public subscript<Element: Hashable>(element element: Element) -> Int { 0 }
    }

    public struct OverloadedInitializerTest {
        public init(_ value: Int) {}
        public init(_ value: String) {}
        public init(_ value: Double) {}
        public init(first: Int, second: Int) {}
        public init<Element>(element: Element) {}
    }
}
```

- [ ] **Step 3: Write `UnsafePointers.swift`**

```swift
import Foundation

public enum UnsafePointers {
    public struct UnsafePointerFieldTest {
        public var readPointer: UnsafePointer<Int>
        public var mutablePointer: UnsafeMutablePointer<Int>
        public var rawPointer: UnsafeRawPointer
        public var mutableRawPointer: UnsafeMutableRawPointer
        public var bufferPointer: UnsafeBufferPointer<Int>
        public var mutableBufferPointer: UnsafeMutableBufferPointer<Int>
        public var rawBufferPointer: UnsafeRawBufferPointer
        public var opaquePointer: OpaquePointer

        public init(
            readPointer: UnsafePointer<Int>,
            mutablePointer: UnsafeMutablePointer<Int>,
            rawPointer: UnsafeRawPointer,
            mutableRawPointer: UnsafeMutableRawPointer,
            bufferPointer: UnsafeBufferPointer<Int>,
            mutableBufferPointer: UnsafeMutableBufferPointer<Int>,
            rawBufferPointer: UnsafeRawBufferPointer,
            opaquePointer: OpaquePointer
        ) {
            self.readPointer = readPointer
            self.mutablePointer = mutablePointer
            self.rawPointer = rawPointer
            self.mutableRawPointer = mutableRawPointer
            self.bufferPointer = bufferPointer
            self.mutableBufferPointer = mutableBufferPointer
            self.rawBufferPointer = rawBufferPointer
            self.opaquePointer = opaquePointer
        }
    }

    public struct UnmanagedFieldTest {
        public var unmanagedReference: Unmanaged<AnyObject>

        public init(unmanagedReference: Unmanaged<AnyObject>) {
            self.unmanagedReference = unmanagedReference
        }
    }

    public struct AutoreleasingPointerFieldTest {
        public var autoreleasing: AutoreleasingUnsafeMutablePointer<AnyObject?>

        public init(autoreleasing: AutoreleasingUnsafeMutablePointer<AnyObject?>) {
            self.autoreleasing = autoreleasing
        }
    }
}
```

- [ ] **Step 4: Build fixture**

Run the Build Verification Command. Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Tests/Projects/SymbolTests/SymbolTestsCore/ProtocolComposition.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/OverloadedMembers.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/UnsafePointers.swift
git commit -m "test(fixture): add ProtocolComposition, OverloadedMembers, UnsafePointers"
```

---

## Task 11: AsyncSequence, PropertyWrapperVariants, CustomLiterals

**Files:**
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/AsyncSequence.swift`
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/PropertyWrapperVariants.swift`
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/CustomLiterals.swift`

- [ ] **Step 1: Write `AsyncSequence.swift`**

```swift
import Foundation

public enum AsyncSequenceTests {
    public struct AsyncSequenceTest: AsyncSequence {
        public typealias Element = Int

        public struct AsyncIterator: AsyncIteratorProtocol {
            public mutating func next() async -> Element? {
                nil
            }
        }

        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator()
        }
    }

    public struct ThrowingAsyncSequenceTest: AsyncSequence {
        public typealias Element = String

        public struct AsyncIterator: AsyncIteratorProtocol {
            public mutating func next() async throws -> Element? {
                nil
            }
        }

        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator()
        }
    }

    public struct GenericAsyncSequenceTest<Element: Sendable>: AsyncSequence {
        public struct AsyncIterator: AsyncIteratorProtocol {
            public mutating func next() async -> Element? {
                nil
            }
        }

        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator()
        }
    }
}
```

- [ ] **Step 2: Write `PropertyWrapperVariants.swift`**

```swift
import Foundation

public enum PropertyWrapperVariants {
    @propertyWrapper
    public struct ProjectedValueWrapperTest<Value> {
        private var storage: Value
        public var wrappedValue: Value {
            get { storage }
            set { storage = newValue }
        }
        public var projectedValue: ProjectedValueWrapperTest<Value> {
            self
        }

        public init(wrappedValue: Value) {
            self.storage = wrappedValue
        }
    }

    @propertyWrapper
    public struct DefaultInitializableWrapperTest {
        public var wrappedValue: Int

        public init() {
            self.wrappedValue = 0
        }

        public init(wrappedValue: Int) {
            self.wrappedValue = wrappedValue
        }
    }

    @propertyWrapper
    public struct StaticSubscriptWrapperTest<Enclosing: AnyObject, Value> {
        public static subscript(
            _enclosingInstance instance: Enclosing,
            wrapped wrappedKeyPath: ReferenceWritableKeyPath<Enclosing, Value>,
            storage storageKeyPath: ReferenceWritableKeyPath<Enclosing, Self>
        ) -> Value {
            get {
                instance[keyPath: storageKeyPath].storage
            }
            set {
                instance[keyPath: storageKeyPath].storage = newValue
            }
        }

        @available(*, unavailable)
        public var wrappedValue: Value {
            get { fatalError() }
            set { fatalError() }
        }

        private var storage: Value

        public init(wrappedValue: Value) {
            self.storage = wrappedValue
        }
    }
}
```

- [ ] **Step 3: Write `CustomLiterals.swift`**

```swift
import Foundation

public enum CustomLiterals {
    public struct IntegerLiteralTest: ExpressibleByIntegerLiteral {
        public let value: Int64
        public init(integerLiteral value: Int64) {
            self.value = value
        }
    }

    public struct StringLiteralTest: ExpressibleByStringLiteral, ExpressibleByUnicodeScalarLiteral, ExpressibleByExtendedGraphemeClusterLiteral {
        public let value: String

        public init(stringLiteral value: String) {
            self.value = value
        }

        public init(unicodeScalarLiteral value: String) {
            self.value = value
        }

        public init(extendedGraphemeClusterLiteral value: String) {
            self.value = value
        }
    }

    public struct ArrayLiteralTest: ExpressibleByArrayLiteral {
        public let elements: [Int]

        public init(arrayLiteral elements: Int...) {
            self.elements = elements
        }
    }

    public struct DictionaryLiteralTest: ExpressibleByDictionaryLiteral {
        public let elements: [String: Int]

        public init(dictionaryLiteral elements: (String, Int)...) {
            var dictionary: [String: Int] = [:]
            for (key, value) in elements {
                dictionary[key] = value
            }
            self.elements = dictionary
        }
    }

    public struct BooleanLiteralTest: ExpressibleByBooleanLiteral {
        public let value: Bool
        public init(booleanLiteral value: Bool) {
            self.value = value
        }
    }

    public struct FloatLiteralTest: ExpressibleByFloatLiteral {
        public let value: Double
        public init(floatLiteral value: Double) {
            self.value = value
        }
    }

    public struct NilLiteralTest: ExpressibleByNilLiteral {
        public init(nilLiteral: ()) {}
    }
}
```

- [ ] **Step 4: Build fixture**

Run the Build Verification Command. Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Tests/Projects/SymbolTests/SymbolTestsCore/AsyncSequence.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/PropertyWrapperVariants.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/CustomLiterals.swift
git commit -m "test(fixture): add AsyncSequence, PropertyWrapperVariants, CustomLiterals"
```

---

## Task 12: StaticMembers, ClassBoundGenerics, MarkerProtocols

**Files:**
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/StaticMembers.swift`
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/ClassBoundGenerics.swift`
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/MarkerProtocols.swift`

- [ ] **Step 1: Write `StaticMembers.swift`**

```swift
import Foundation

public enum StaticMembers {
    public struct StaticMemberStructTest {
        public static let storedConstant: Int = 0
        public static var storedMutable: String = ""
        public static var computedProperty: Int {
            get { 0 }
            set {}
        }

        public static func staticMethod() -> Int { 0 }
        public static func staticGenericMethod<Element>(_ element: Element) -> Element { element }

        public static subscript(index: Int) -> String {
            String(index)
        }
    }

    public class StaticMemberClassTest {
        public static let storedConstant: Int = 0
        public static var storedMutable: String = ""
        public class var classComputed: Int { 0 }

        public static func staticMethod() -> Int { 0 }
        public class func classMethod() -> Int { 0 }

        public init() {}
    }

    public class StaticMemberSubclassTest: StaticMemberClassTest {
        public override class var classComputed: Int { 1 }
        public override class func classMethod() -> Int { 1 }
    }
}
```

- [ ] **Step 2: Write `ClassBoundGenerics.swift`**

```swift
import Foundation

public enum ClassBoundGenerics {
    public struct AnyObjectBoundTest<Element: AnyObject> {
        public var element: Element
        public init(element: Element) {
            self.element = element
        }
    }

    public struct AnyObjectAndProtocolBoundTest<Element> where Element: AnyObject, Element: Protocols.ProtocolTest {
        public var element: Element
        public init(element: Element) {
            self.element = element
        }
    }

    public class ClassBoundGenericClassTest<Element: AnyObject> {
        public var element: Element
        public init(element: Element) {
            self.element = element
        }
    }

    public protocol ClassBoundGenericProtocol: AnyObject {
        associatedtype Item: AnyObject
        var item: Item { get }
    }

    public struct ClassBoundFunctionTest {
        public func acceptClassBound<Element: AnyObject>(_ element: Element) -> Element {
            element
        }

        public func acceptClassAndProtocol<Element>(_ element: Element) -> Element where Element: AnyObject, Element: Protocols.ProtocolTest {
            element
        }
    }
}
```

- [ ] **Step 3: Write `MarkerProtocols.swift`**

```swift
import Foundation

public enum MarkerProtocols {
    public protocol MarkerProtocolTest {}

    public protocol EmptyMarkerProtocolTest {}

    public protocol ClassBoundMarkerProtocol: AnyObject {}

    public protocol InheritingMarkerProtocol: MarkerProtocolTest {}

    public struct MarkerConformingStructTest: MarkerProtocolTest, EmptyMarkerProtocolTest {
        public var value: Int
        public init(value: Int) {
            self.value = value
        }
    }

    public class MarkerConformingClassTest: ClassBoundMarkerProtocol, InheritingMarkerProtocol {
        public var label: String
        public init(label: String) {
            self.label = label
        }
    }

    public enum MarkerConformingEnumTest: MarkerProtocolTest {
        case first
        case second
    }
}
```

- [ ] **Step 4: Build fixture**

Run the Build Verification Command. Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Tests/Projects/SymbolTests/SymbolTestsCore/StaticMembers.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/ClassBoundGenerics.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/MarkerProtocols.swift
git commit -m "test(fixture): add StaticMembers, ClassBoundGenerics, MarkerProtocols"
```

---

## Task 13: DependentTypeAccess, DeinitVariants, CollectionConformances

**Files:**
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/DependentTypeAccess.swift`
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/DeinitVariants.swift`
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/CollectionConformances.swift`

- [ ] **Step 1: Write `DependentTypeAccess.swift`**

```swift
import Foundation

public enum DependentTypeAccess {
    public protocol DependentProtocol {
        associatedtype First
        associatedtype Second: Collection where Second.Element == First
    }

    public struct DependentAccessTest<Element: Collection> {
        public var iteratorElement: Element.Iterator.Element?
        public var indicesIndex: Element.Indices.Element?
        public var subSequenceIndex: Element.SubSequence.Index?

        public init(
            iteratorElement: Element.Iterator.Element?,
            indicesIndex: Element.Indices.Element?,
            subSequenceIndex: Element.SubSequence.Index?
        ) {
            self.iteratorElement = iteratorElement
            self.indicesIndex = indicesIndex
            self.subSequenceIndex = subSequenceIndex
        }
    }

    public struct DeepDependentAccessTest<Element: Collection> where Element.SubSequence: Collection {
        public var deepElement: Element.SubSequence.SubSequence.Element?

        public init(deepElement: Element.SubSequence.SubSequence.Element?) {
            self.deepElement = deepElement
        }
    }

    public struct DependentFunctionTest {
        public func acceptDependent<Element: Collection>(
            _ element: Element,
            iteratorElement: Element.Iterator.Element,
            indicesElement: Element.Indices.Element
        ) -> Element.SubSequence {
            element[element.startIndex..<element.endIndex]
        }
    }
}
```

- [ ] **Step 2: Write `DeinitVariants.swift`**

```swift
import Foundation

public enum DeinitVariants {
    public class SimpleDeinitTest {
        public var value: Int = 0
        public init() {}
        deinit {}
    }

    public class DeinitWithWorkTest {
        public var resource: Int = 0
        public init() {}
        deinit {
            resource = 0
        }
    }

    public actor ActorDeinitTest {
        public var state: Int = 0
        public init() {}
        deinit {}
    }

    public class GenericDeinitTest<Element> {
        public var element: Element
        public init(element: Element) {
            self.element = element
        }
        deinit {}
    }
}
```

Note: `isolated deinit` was considered but omitted because it is still experimental. Only include it if `swift-syntax` tooling confirms stable support on the current toolchain.

- [ ] **Step 3: Write `CollectionConformances.swift`**

```swift
import Foundation

public enum CollectionConformances {
    public struct CustomSequenceTest: Sequence {
        public struct Iterator: IteratorProtocol {
            public mutating func next() -> Int? { nil }
        }

        public func makeIterator() -> Iterator {
            Iterator()
        }
    }

    public struct CustomCollectionTest: Collection {
        public var startIndex: Int { 0 }
        public var endIndex: Int { 0 }

        public subscript(position: Int) -> Int { 0 }

        public func index(after index: Int) -> Int {
            index + 1
        }
    }

    public struct CustomBidirectionalCollectionTest: BidirectionalCollection {
        public var startIndex: Int { 0 }
        public var endIndex: Int { 0 }

        public subscript(position: Int) -> String { "" }

        public func index(after index: Int) -> Int {
            index + 1
        }

        public func index(before index: Int) -> Int {
            index - 1
        }
    }

    public struct CustomRandomAccessCollectionTest: RandomAccessCollection {
        public var startIndex: Int { 0 }
        public var endIndex: Int { 0 }

        public subscript(position: Int) -> Double { 0.0 }

        public func index(after index: Int) -> Int {
            index + 1
        }

        public func index(before index: Int) -> Int {
            index - 1
        }
    }
}
```

- [ ] **Step 4: Build fixture**

Run the Build Verification Command. Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Tests/Projects/SymbolTests/SymbolTestsCore/DependentTypeAccess.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/DeinitVariants.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/CollectionConformances.swift
git commit -m "test(fixture): add DependentTypeAccess, DeinitVariants, CollectionConformances"
```

---

## Task 14: FieldDescriptorVariants, GenericRequirementVariants

**Files:**
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/FieldDescriptorVariants.swift`
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/GenericRequirementVariants.swift`

- [ ] **Step 1: Write `FieldDescriptorVariants.swift`**

```swift
import Foundation

public enum FieldDescriptorVariants {
    public struct VarLetFieldTest {
        public var mutableField: Int
        public let immutableField: String
        public var mutableOptional: Double?
        public let immutableOptional: Int?

        public init(mutableField: Int, immutableField: String, mutableOptional: Double?, immutableOptional: Int?) {
            self.mutableField = mutableField
            self.immutableField = immutableField
            self.mutableOptional = mutableOptional
            self.immutableOptional = immutableOptional
        }
    }

    public class ReferenceFieldTest {
        public weak var weakField: AnyObject?
        public unowned var unownedField: AnyObject
        public unowned(unsafe) var unownedUnsafeField: AnyObject
        public var strongField: AnyObject

        public init(reference: AnyObject) {
            self.unownedField = reference
            self.unownedUnsafeField = reference
            self.strongField = reference
        }
    }

    public struct MangledNameVariantsTest<Element> {
        public var concreteInt: Int
        public var concreteString: String
        public var genericElement: Element
        public var arrayOfElement: [Element]
        public var dictionaryOfElement: [String: Element]
        public var optionalElement: Element?
        public var tupleField: (Int, Element)
        public var functionField: (Element) -> Int

        public init(
            concreteInt: Int,
            concreteString: String,
            genericElement: Element,
            arrayOfElement: [Element],
            dictionaryOfElement: [String: Element],
            optionalElement: Element?,
            tupleField: (Int, Element),
            functionField: @escaping (Element) -> Int
        ) {
            self.concreteInt = concreteInt
            self.concreteString = concreteString
            self.genericElement = genericElement
            self.arrayOfElement = arrayOfElement
            self.dictionaryOfElement = dictionaryOfElement
            self.optionalElement = optionalElement
            self.tupleField = tupleField
            self.functionField = functionField
        }
    }
}
```

- [ ] **Step 2: Write `GenericRequirementVariants.swift`**

```swift
import Foundation

public enum GenericRequirementVariants {
    public struct ProtocolRequirementTest<Element: Protocols.ProtocolTest> {
        public var element: Element
        public init(element: Element) { self.element = element }
    }

    public struct SameTypeRequirementTest<First, Second> where First == Second {
        public var first: First
        public var second: Second

        public init(first: First, second: Second) {
            self.first = first
            self.second = second
        }
    }

    public class GenericBaseClassForRequirementTest {
        public var baseField: Int = 0
        public init() {}
    }

    public struct BaseClassRequirementTest<Element: GenericBaseClassForRequirementTest> {
        public var element: Element
        public init(element: Element) { self.element = element }
    }

    public struct LayoutAnyObjectRequirementTest<Element: AnyObject> {
        public var element: Element
        public init(element: Element) { self.element = element }
    }

    public struct SameShapePackRequirementTest<each First, each Second> {
        public var first: (repeat each First)
        public var second: (repeat each Second)

        public init(first: (repeat each First), second: (repeat each Second)) {
            self.first = first
            self.second = second
        }
    }

    public struct InvertibleProtocolRequirementTest<Element: ~Copyable>: ~Copyable {
        public var element: Element

        public init(element: consuming Element) {
            self.element = element
        }
    }
}
```

- [ ] **Step 3: Build fixture**

Run the Build Verification Command.
Expected: build succeeds. If the parameter pack declaration produces a "same-shape inference" diagnostic, add an explicit `where (repeat (each First, each Second)): Any` constraint.

- [ ] **Step 4: Commit**

```bash
git add Tests/Projects/SymbolTests/SymbolTestsCore/FieldDescriptorVariants.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/GenericRequirementVariants.swift
git commit -m "test(fixture): add FieldDescriptorVariants and GenericRequirementVariants"
```

---

## Task 15: VTableEntryVariants, ConditionalConformanceVariants

**Files:**
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/VTableEntryVariants.swift`
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/ConditionalConformanceVariants.swift`

- [ ] **Step 1: Write `VTableEntryVariants.swift`**

```swift
import Foundation

public enum VTableEntryVariants {
    public class VTableBaseTest {
        public func normalMethod() {}
        public func overridableMethod() -> Int { 0 }
        public final func finalMethod() {}
        public func asyncMethod() async -> Int { 0 }
        public func throwingMethod() throws -> Int { 0 }
        public func asyncThrowingMethod() async throws -> Int { 0 }

        public var normalProperty: Int {
            get { 0 }
            set {}
        }

        public var asyncProperty: Int {
            get async { 0 }
        }

        public var throwingProperty: Int {
            get throws { 0 }
        }

        public init() {}
    }

    public class VTableOverrideTest: VTableBaseTest {
        public override func overridableMethod() -> Int { 1 }
        public override func asyncMethod() async -> Int { 1 }
        public override func throwingMethod() throws -> Int { 1 }
    }

    public final class VTableFinalOverrideTest: VTableBaseTest {
        public override func overridableMethod() -> Int { 2 }
    }

    public class VTableDeepOverrideTest: VTableOverrideTest {
        public override func overridableMethod() -> Int { 3 }
        public override func asyncMethod() async -> Int { 3 }
    }
}
```

- [ ] **Step 2: Write `ConditionalConformanceVariants.swift`**

```swift
import Foundation

public enum ConditionalConformanceVariants {
    public struct ConditionalContainerTest<Element> {
        public var element: Element
        public init(element: Element) { self.element = element }
    }

    public protocol ConditionalFirstProtocol {}
    public protocol ConditionalSecondProtocol {}
    public protocol ConditionalThirdProtocol {}
}

extension ConditionalConformanceVariants.ConditionalContainerTest: Equatable where Element: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.element == rhs.element
    }
}

extension ConditionalConformanceVariants.ConditionalContainerTest: Hashable where Element: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(element)
    }
}

extension ConditionalConformanceVariants.ConditionalContainerTest: Comparable where Element: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.element < rhs.element
    }
}

extension ConditionalConformanceVariants.ConditionalContainerTest: Sendable where Element: Sendable {}

extension ConditionalConformanceVariants.ConditionalContainerTest: ConditionalConformanceVariants.ConditionalFirstProtocol
where Element: ConditionalConformanceVariants.ConditionalFirstProtocol {}

extension ConditionalConformanceVariants.ConditionalContainerTest: ConditionalConformanceVariants.ConditionalSecondProtocol
where Element: ConditionalConformanceVariants.ConditionalFirstProtocol & ConditionalConformanceVariants.ConditionalSecondProtocol {}

extension ConditionalConformanceVariants.ConditionalContainerTest: ConditionalConformanceVariants.ConditionalThirdProtocol
where Element: ConditionalConformanceVariants.ConditionalFirstProtocol,
      Element: ConditionalConformanceVariants.ConditionalSecondProtocol,
      Element: ConditionalConformanceVariants.ConditionalThirdProtocol {}
```

- [ ] **Step 3: Build fixture**

Run the Build Verification Command. Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Tests/Projects/SymbolTests/SymbolTestsCore/VTableEntryVariants.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/ConditionalConformanceVariants.swift
git commit -m "test(fixture): add VTableEntryVariants and ConditionalConformanceVariants"
```

---

## Task 16: DefaultImplementationVariants, FrozenResilienceContrast

**Files:**
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/DefaultImplementationVariants.swift`
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/FrozenResilienceContrast.swift`

- [ ] **Step 1: Write `DefaultImplementationVariants.swift`**

```swift
import Foundation

public enum DefaultImplementationVariants {
    public protocol BasicDefaultProtocol {
        func required() -> Int
        func withDefault() -> String
        func withDefaultAndGeneric<Element>(_ element: Element) -> Element
    }

    public protocol ConstrainedDefaultProtocol {
        associatedtype Element
        var element: Element { get }
    }
}

extension DefaultImplementationVariants.BasicDefaultProtocol {
    public func withDefault() -> String {
        "default"
    }

    public func withDefaultAndGeneric<Element>(_ element: Element) -> Element {
        element
    }
}

extension DefaultImplementationVariants.ConstrainedDefaultProtocol where Element: Equatable {
    public func isEqualTo(_ other: Element) -> Bool {
        element == other
    }
}

extension DefaultImplementationVariants.ConstrainedDefaultProtocol where Element: Comparable {
    public func isLessThan(_ other: Element) -> Bool {
        element < other
    }
}

extension DefaultImplementationVariants.ConstrainedDefaultProtocol where Element: Hashable & Sendable {
    public func computeHash() -> Int {
        element.hashValue
    }
}

extension DefaultImplementationVariants.ConstrainedDefaultProtocol where Element: AnyObject {
    public func identityCheck(_ other: Element) -> Bool {
        element === other
    }
}
```

- [ ] **Step 2: Write `FrozenResilienceContrast.swift`**

```swift
import Foundation

public enum FrozenResilienceContrast {
    @frozen
    public struct FrozenStructTest {
        public var firstField: Int
        public var secondField: Double
        public var thirdField: String

        public init(firstField: Int, secondField: Double, thirdField: String) {
            self.firstField = firstField
            self.secondField = secondField
            self.thirdField = thirdField
        }
    }

    public struct ResilientStructTest {
        public var firstField: Int
        public var secondField: Double
        public var thirdField: String

        public init(firstField: Int, secondField: Double, thirdField: String) {
            self.firstField = firstField
            self.secondField = secondField
            self.thirdField = thirdField
        }
    }

    @frozen
    public enum FrozenEnumContrastTest {
        case empty
        case integer(Int)
        case string(String)
        case pair(Int, Double)
    }

    public enum ResilientEnumContrastTest {
        case empty
        case integer(Int)
        case string(String)
        case pair(Int, Double)
    }

    @frozen
    public struct FrozenGenericTest<Element> {
        public var element: Element
        public var count: Int

        public init(element: Element, count: Int) {
            self.element = element
            self.count = count
        }
    }

    public struct ResilientGenericTest<Element> {
        public var element: Element
        public var count: Int

        public init(element: Element, count: Int) {
            self.element = element
            self.count = count
        }
    }
}
```

- [ ] **Step 3: Build fixture**

Run the Build Verification Command. Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Tests/Projects/SymbolTests/SymbolTestsCore/DefaultImplementationVariants.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/FrozenResilienceContrast.swift
git commit -m "test(fixture): add DefaultImplementationVariants and FrozenResilienceContrast"
```

---

## Task 17: AssociatedTypeWitnessPatterns, BuiltinTypeFields

**Files:**
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/AssociatedTypeWitnessPatterns.swift`
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/BuiltinTypeFields.swift`

- [ ] **Step 1: Write `AssociatedTypeWitnessPatterns.swift`**

```swift
import Foundation

public enum AssociatedTypeWitnessPatterns {
    public protocol AssociatedPatternProtocol {
        associatedtype First
        associatedtype Second: Collection
        associatedtype Third
        associatedtype Fourth
        associatedtype Fifth
    }

    public struct ConcreteWitnessTest: AssociatedPatternProtocol {
        public typealias First = Int
        public typealias Second = [String]
        public typealias Third = Double
        public typealias Fourth = Bool
        public typealias Fifth = Character
    }

    public struct NestedWitnessTest: AssociatedPatternProtocol {
        public struct NestedFirst {}
        public struct NestedThird {}

        public typealias First = NestedFirst
        public typealias Second = [NestedFirst]
        public typealias Third = NestedThird
        public typealias Fourth = (NestedFirst, NestedThird)
        public typealias Fifth = NestedFirst?
    }

    public struct GenericParameterWitnessTest<Element>: AssociatedPatternProtocol {
        public typealias First = Element
        public typealias Second = [Element]
        public typealias Third = Element?
        public typealias Fourth = (Element, Element)
        public typealias Fifth = [String: Element]
    }

    public struct RecursiveWitnessTest: AssociatedPatternProtocol {
        public typealias First = RecursiveWitnessTest
        public typealias Second = [RecursiveWitnessTest]
        public typealias Third = RecursiveWitnessTest?
        public typealias Fourth = (RecursiveWitnessTest, RecursiveWitnessTest)
        public typealias Fifth = [String: RecursiveWitnessTest]
    }

    public struct DependentWitnessTest<Element: Collection>: AssociatedPatternProtocol {
        public typealias First = Element.Element
        public typealias Second = Element
        public typealias Third = Element.Iterator
        public typealias Fourth = Element.Index
        public typealias Fifth = Element.SubSequence
    }
}
```

- [ ] **Step 2: Write `BuiltinTypeFields.swift`**

```swift
import Foundation

public enum BuiltinTypeFields {
    public struct IntegerTypesTest {
        public var intField: Int
        public var int8Field: Int8
        public var int16Field: Int16
        public var int32Field: Int32
        public var int64Field: Int64
        public var uintField: UInt
        public var uint8Field: UInt8
        public var uint16Field: UInt16
        public var uint32Field: UInt32
        public var uint64Field: UInt64

        public init(
            intField: Int,
            int8Field: Int8,
            int16Field: Int16,
            int32Field: Int32,
            int64Field: Int64,
            uintField: UInt,
            uint8Field: UInt8,
            uint16Field: UInt16,
            uint32Field: UInt32,
            uint64Field: UInt64
        ) {
            self.intField = intField
            self.int8Field = int8Field
            self.int16Field = int16Field
            self.int32Field = int32Field
            self.int64Field = int64Field
            self.uintField = uintField
            self.uint8Field = uint8Field
            self.uint16Field = uint16Field
            self.uint32Field = uint32Field
            self.uint64Field = uint64Field
        }
    }

    public struct FloatingTypesTest {
        public var floatField: Float
        public var doubleField: Double
        public var float32Field: Float32
        public var float64Field: Float64

        public init(floatField: Float, doubleField: Double, float32Field: Float32, float64Field: Float64) {
            self.floatField = floatField
            self.doubleField = doubleField
            self.float32Field = float32Field
            self.float64Field = float64Field
        }
    }

    public struct PrimitiveTypesTest {
        public var boolField: Bool
        public var characterField: Character
        public var stringField: String

        public init(boolField: Bool, characterField: Character, stringField: String) {
            self.boolField = boolField
            self.characterField = characterField
            self.stringField = stringField
        }
    }

    public struct TupleBuiltinTest {
        public var pairField: (Int, Double)
        public var tripleField: (Int, Double, Bool)
        public var quadrupleField: (Int8, Int16, Int32, Int64)

        public init(pairField: (Int, Double), tripleField: (Int, Double, Bool), quadrupleField: (Int8, Int16, Int32, Int64)) {
            self.pairField = pairField
            self.tripleField = tripleField
            self.quadrupleField = quadrupleField
        }
    }
}
```

- [ ] **Step 3: Build fixture**

Run the Build Verification Command. Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Tests/Projects/SymbolTests/SymbolTestsCore/AssociatedTypeWitnessPatterns.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/BuiltinTypeFields.swift
git commit -m "test(fixture): add AssociatedTypeWitnessPatterns and BuiltinTypeFields"
```

---

## Task 18: Edits to existing files

**Files:**
- Modify: `Tests/Projects/SymbolTests/SymbolTestsCore/Classes.swift`
- Modify: `Tests/Projects/SymbolTests/SymbolTestsCore/Enums.swift`
- Modify: `Tests/Projects/SymbolTests/SymbolTestsCore/FunctionFeatures.swift`
- Modify: `Tests/Projects/SymbolTests/SymbolTestsCore/Protocols.swift`

- [ ] **Step 1: Extend `Classes.swift`**

Add these nested types inside the existing `public enum Classes { ... }` block (place before the closing `}`):

```swift
    public class RequiredInitClassTest {
        public let identifier: Int
        public required init(identifier: Int) {
            self.identifier = identifier
        }
    }

    public class DefaultParameterClassTest {
        public func method(first: Int = 0, second: String = "default") -> Int {
            first
        }

        public class func classMethod(value: Int = 42) -> Int {
            value
        }

        public init() {}
    }
```

- [ ] **Step 2: Extend `Enums.swift`**

Add these nested enums inside the existing `public enum Enums { ... }` block:

```swift
    @frozen
    public enum LargeFrozenEnumTest {
        case alpha
        case beta
        case gamma
        case delta
        case epsilon
        case zeta
        case eta
        case theta
        case iota
        case kappa
    }

    public enum GenericPayloadEnumTest<Element> {
        case first(Element)
        case second(Element, Element)
        case empty
    }

    public enum FunctionReferenceCaseTest {
        case first(Int)
        case second(String)

        public static func selectFirst() -> (Int) -> FunctionReferenceCaseTest {
            FunctionReferenceCaseTest.first
        }
    }
```

- [ ] **Step 3: Extend `FunctionFeatures.swift`**

Add these nested structs inside the existing `public enum FunctionFeatures { ... }` block:

```swift
    public struct MainActorClosureTest {
        public func acceptMainActorClosure(_ callback: @MainActor () -> Void) {}
        public func acceptMainActorAsync(_ callback: @MainActor () async -> Void) {}
    }

    public struct DefaultParameterFunctionTest {
        public func defaultMethod(value: Int = 0, label: String = "default", flag: Bool = true) -> String {
            label
        }

        public static func staticDefault(first: Int = 0, second: Int = 1) -> Int {
            first + second
        }
    }
```

- [ ] **Step 4: Extend `Protocols.swift`**

Add these protocols inside the existing `public enum Protocols { ... }` block:

```swift
    public protocol SelfConstraintProtocolTest where Self: AnyObject, Self: Sendable {
        func method() -> Self
    }

    public protocol MultiPrimaryAssociatedTypeTest<First, Second, Third> {
        associatedtype First
        associatedtype Second
        associatedtype Third
    }
```

- [ ] **Step 5: Build fixture**

Run the Build Verification Command. Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Tests/Projects/SymbolTests/SymbolTestsCore/Classes.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/Enums.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/FunctionFeatures.swift \
        Tests/Projects/SymbolTests/SymbolTestsCore/Protocols.swift
git commit -m "test(fixture): extend Classes, Enums, FunctionFeatures, Protocols"
```

---

## Task 19: Regenerate snapshot and run full SwiftInterfaceTests

The `MachOFileInterfaceSnapshotTests` compares the full SwiftInterface output of `SymbolTestsCore` against a stored snapshot. Because every prior task added new symbols, this snapshot is now stale.

**Files:**
- Delete: `Tests/SwiftInterfaceTests/Snapshots/__Snapshots__/MachOFileInterfaceSnapshotTests/interfaceSnapshot.1.txt`
- Regenerate: same path, from test run
- Run: `swift test --filter SwiftInterfaceTests`

- [ ] **Step 1: Update package dependencies**

Run: `swift package update`
Expected: resolves dependencies; no errors.

- [ ] **Step 2: Delete the stale snapshot**

Run:
```bash
rm Tests/SwiftInterfaceTests/Snapshots/__Snapshots__/MachOFileInterfaceSnapshotTests/interfaceSnapshot.1.txt
```

- [ ] **Step 3: Run the snapshot test to regenerate**

Run: `swift test --filter MachOFileInterfaceSnapshotTests 2>&1 | xcsift`
Expected: the test "fails" the first time with a `.missing` record mode notice and writes a new `interfaceSnapshot.1.txt` file. Re-run the same command; the second run should pass against the newly-generated snapshot.

- [ ] **Step 4: Inspect the regenerated snapshot**

Run: `wc -l Tests/SwiftInterfaceTests/Snapshots/__Snapshots__/MachOFileInterfaceSnapshotTests/interfaceSnapshot.1.txt`
Expected: substantially larger than the original 930 lines (now should be ~2500–3500 lines including all new types).

Spot-check the snapshot to confirm a sampling of new types are present:

```bash
grep -E "KeyPaths|DistributedActors|FieldDescriptorVariants|OverloadedMethodTest" \
  Tests/SwiftInterfaceTests/Snapshots/__Snapshots__/MachOFileInterfaceSnapshotTests/interfaceSnapshot.1.txt | head -20
```
Expected: each pattern matched at least once.

- [ ] **Step 5: Run the complete SwiftInterfaceTests suite**

Run: `swift test --filter SwiftInterfaceTests 2>&1 | xcsift`
Expected: all tests pass. If any existing test fails because it hard-codes a condition only true on the old fixture shape (e.g., expected type count), fix the test to be robust to the new shape rather than reverting fixture changes.

- [ ] **Step 6: Commit regenerated snapshot**

```bash
git add Tests/SwiftInterfaceTests/Snapshots/__Snapshots__/MachOFileInterfaceSnapshotTests/interfaceSnapshot.1.txt
git commit -m "test(snapshot): regenerate MachOFileInterfaceSnapshot for expanded fixture"
```

---

## Final verification checklist

After Task 19 is committed, do a quick sanity check on the whole branch:

- [ ] Run the full test suite: `swift test 2>&1 | xcsift`.
- [ ] Confirm no test target regressed beyond `MachOFileInterfaceSnapshotTests` (whose snapshot was intentionally updated).
- [ ] `git log --oneline feature/vtable-offset-and-member-ordering` should show 19 new test-fixture commits.
- [ ] Spot-check that `Tests/Projects/SymbolTests/SymbolTestsCore/` now contains 62 files (18 pre-existing + 44 new).
