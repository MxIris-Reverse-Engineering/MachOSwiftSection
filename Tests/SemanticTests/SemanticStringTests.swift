import Testing
@testable import Semantic

@Suite("SemanticString Tests")
struct SemanticStringTests {
    // MARK: - Initialization Tests

    @Test("Empty initialization")
    func emptyInit() {
        let ss = SemanticString()
        #expect(ss.isEmpty)
        #expect(ss.count == 0)
        #expect(ss.string == "")
    }

    @Test("String literal initialization")
    func stringLiteralInit() {
        let ss: SemanticString = "Hello"
        #expect(!ss.isEmpty)
        #expect(ss.count == 1)
        #expect(ss.string == "Hello")
        #expect(ss.first?.type == .standard)
    }

    @Test("Component initialization")
    func componentInit() {
        let ss = SemanticString(Keyword("public"))
        #expect(ss.count == 1)
        #expect(ss.string == "public")
        #expect(ss.first?.type == .keyword)
    }

    @Test("Builder initialization")
    func builderInit() {
        let ss = SemanticString {
            Keyword("public")
            Space()
            Keyword("struct")
        }
        #expect(ss.count == 3)
        #expect(ss.string == "public struct")
    }

    // MARK: - SemanticStringComponent Protocol Tests

    @Test("Atomic component builds to single element")
    func atomicComponentBuild() {
        let keyword = Keyword("func")
        let components = keyword.buildComponents()
        #expect(components.count == 1)
        #expect(components[0].string == "func")
        #expect(components[0].type == .keyword)
    }

    @Test("Empty string component builds to empty array")
    func emptyComponentBuild() {
        let empty = Standard("")
        let components = empty.buildComponents()
        #expect(components.isEmpty)
    }

    @Test("SemanticString conforms to SemanticStringComponent")
    func semanticStringAsComponent() {
        let ss = SemanticString {
            Keyword("let")
            Space()
            Variable("x")
        }
        let components = ss.buildComponents()
        #expect(components.count == 3)
    }

    // MARK: - Composite Component Tests

    @Test("Group component")
    func groupComponent() {
        let group = Group {
            Keyword("public")
            Keyword("static")
            Keyword("func")
        }
        let components = group.buildComponents()
        #expect(components.count == 3)
        #expect(components.map(\.string).joined() == "publicstaticfunc")
    }

    @Test("Group with separator using conditionals")
    func groupWithSeparator() {
        let isPublic = true
        let isStatic = true
        let group = Group {
            if isPublic {
                Keyword("public")
            }
            if isStatic {
                Keyword("static")
            }
        }.separator(Space())

        let components = group.buildComponents()
        #expect(components.count == 3) // public, space, static
        #expect(components.map(\.string).joined() == "public static")
    }

    @Test("Group with array")
    func groupWithArray() {
        let items = ["a", "b", "c"].map { SemanticString(Standard($0)) }
        let group = Group(items).separator(", ")
        let components = group.buildComponents()
        #expect(components.map(\.string).joined() == "a, b, c")
    }

    @Test("Joined component with conditionals")
    func joinedComponent() {
        // Joined is designed for conditional blocks where some items may be empty
        let showA = true
        let showB = true
        let showC = true
        let joined = Joined(separator: ", ") {
            if showA {
                Standard("a")
            }
            if showB {
                Standard("b")
            }
            if showC {
                Standard("c")
            }
        }
        #expect(joined.buildComponents().map(\.string).joined() == "a, b, c")
    }

    @Test("Joined skips false conditions")
    func joinedSkipsEmpty() {
        let showA = true
        let showB = false
        let showC = true
        let joined = Joined(separator: ", ") {
            if showA {
                Standard("a")
            }
            if showB {
                Standard("b")
            }
            if showC {
                Standard("c")
            }
        }
        #expect(joined.buildComponents().map(\.string).joined() == "a, c")
    }

    @Test("Joined with array")
    func joinedWithArray() {
        let items = ["a", "b", "c"].map { SemanticString(Standard($0)) }
        let joined = Joined(separator: ", ", items)
        #expect(joined.buildComponents().map(\.string).joined() == "a, b, c")
    }

    @Test("ForEach component")
    func forEachComponent() {
        let items = ["one", "two", "three"]
        let forEach = ForEach(items) { item in
            Standard(item)
        }
        #expect(forEach.buildComponents().map(\.string).joined() == "onetwothree")
    }

    @Test("ForEach with separator")
    func forEachWithSeparator() {
        let items = ["a", "b", "c"]
        let forEach = ForEach(items, separator: "-") { item in
            Standard(item)
        }
        #expect(forEach.buildComponents().map(\.string).joined() == "a-b-c")
    }

    @Test("ForEachIndexed component")
    func forEachIndexedComponent() {
        let items = ["x", "y"]
        let forEach = ForEachIndexed(items) { item, info in
            if !info.isFirst {
                Standard(",")
            }
            Standard(item)
        }
        #expect(forEach.buildComponents().map(\.string).joined() == "x,y")
    }

    @Test("IfLet with value")
    func ifLetWithValue() {
        let value: String? = "hello"
        let ifLet = IfLet(value) { v in
            Standard(v)
        }
        #expect(ifLet.buildComponents().count == 1)
        #expect(ifLet.buildComponents()[0].string == "hello")
    }

    @Test("IfLet without value")
    func ifLetWithoutValue() {
        let value: String? = nil
        let ifLet = IfLet(value) { v in
            Standard(v)
        }
        #expect(ifLet.buildComponents().isEmpty)
    }

    @Test("IfLet with else")
    func ifLetWithElse() {
        let value: String? = nil
        let ifLet = IfLet(value, then: { v in
            Standard(v)
        }, else: {
            Standard("default")
        })
        #expect(ifLet.buildComponents()[0].string == "default")
    }

    // MARK: - Builder Tests

    @Test("Builder with conditionals")
    func builderConditionals() {
        let isPublic = true
        let ss = SemanticString {
            if isPublic {
                Keyword("public")
                Space()
            }
            Keyword("func")
        }
        #expect(ss.string == "public func")
    }

    @Test("Builder with false conditional")
    func builderFalseConditional() {
        let isPublic = false
        let ss = SemanticString {
            if isPublic {
                Keyword("public")
                Space()
            }
            Keyword("func")
        }
        #expect(ss.string == "func")
    }

    @Test("Builder with for loop")
    func builderForLoop() {
        let ss = SemanticString {
            for i in 1...3 {
                Numeric("\(i)")
            }
        }
        #expect(ss.string == "123")
    }

    @Test("Builder with void expressions")
    func builderVoidExpressions() {
        var count = 0
        let ss = SemanticString {
            count += 1
            Keyword("test")
            count += 1
        }
        #expect(ss.string == "test")
        #expect(count == 2)
    }

    // MARK: - Appending Tests

    @Test("Appending semantic strings")
    func appendingSemanticStrings() {
        let a = SemanticString(Keyword("let"))
        let b = SemanticString(Variable("x"))
        let result = a.appending(Space()).appending(b)
        #expect(result.string == "let x")
    }

    @Test("Appending with operator")
    func appendingOperator() {
        let a = SemanticString(Keyword("var"))
        let b = SemanticString(Variable("y"))
        let result = a.appending(Space()).appending(b)
        #expect(result.string == "var y")
    }

    // MARK: - Transformation Tests

    @Test("Map components")
    func mapComponents() {
        let ss = SemanticString {
            Standard("hello")
            Standard("world")
        }
        let mapped = ss.map { AtomicComponent(string: $0.string.uppercased(), type: $0.type) }
        #expect(mapped.string == "HELLOWORLD")
    }

    @Test("Replacing semantic types")
    func replacingTypes() {
        let ss = SemanticString {
            Keyword("let")
            Variable("x")
        }
        let replaced = ss.replacing { _ in .standard }
        #expect(replaced.first?.type == .standard)
        #expect(replaced.last?.type == .standard)
    }

    // MARK: - Conditional Extensions Tests

    @Test("Component if condition true")
    func componentIfTrue() {
        let result = Keyword("public").if(true)
        #expect(result.string == "public")
    }

    @Test("Component if condition false")
    func componentIfFalse() {
        let result = Keyword("public").if(false)
        #expect(result.isEmpty)
    }

    @Test("Prefixed with condition")
    func prefixedWithCondition() {
        let ss = SemanticString(Keyword("func"))
        let result = ss.prefixed(with: "public ", if: true)
        #expect(result.string == "public func")
    }

    @Test("Suffixed with condition")
    func suffixedWithCondition() {
        let ss = SemanticString(TypeName(kind: .other, "Int"))
        let result = ss.suffixed(with: "?", if: true)
        #expect(result.string == "Int?")
    }

    // MARK: - Wrapping Tests

    @Test("Parenthesized")
    func parenthesized() {
        let ss = SemanticString(Standard("content"))
        #expect(ss.parenthesized().string == "(content)")
    }

    @Test("Bracketed")
    func bracketed() {
        let ss = SemanticString(Standard("index"))
        #expect(ss.bracketed().string == "[index]")
    }

    @Test("Angle bracketed")
    func angleBracketed() {
        let ss = SemanticString(TypeName(kind: .other, "T"))
        #expect(ss.angleBracketed().string == "<T>")
    }

    // MARK: - Trimming Tests

    @Test("Trimming whitespace")
    func trimmingWhitespace() {
        let ss = SemanticString {
            Space()
            Keyword("func")
            Space()
        }
        let trimmed = ss.trimmingWhitespace()
        #expect(trimmed.string == "func")
    }

    // MARK: - EmptyComponent Tests

    @Test("Empty component produces no output")
    func emptyComponent() {
        let empty = EmptyComponent()
        #expect(empty.buildComponents().isEmpty)
    }

    @Test("Empty component in builder")
    func emptyComponentInBuilder() {
        let ss = SemanticString {
            Keyword("test")
            EmptyComponent()
            Standard("!")
        }
        #expect(ss.string == "test!")
    }

    // MARK: - Array Extension Tests

    @Test("Array joined with separator")
    func arrayJoined() {
        let items: [SemanticString] = [
            SemanticString(Standard("a")),
            SemanticString(Standard("b")),
            SemanticString(Standard("c"))
        ]
        let result = items.joined(separator: ", ")
        #expect(result.string == "a, b, c")
    }
}
