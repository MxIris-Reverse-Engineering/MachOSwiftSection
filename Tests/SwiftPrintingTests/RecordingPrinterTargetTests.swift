@_spi(Support) @testable import SwiftPrinting
import Demangling
import Testing

/// A `NodePrinterTarget` that records every call the printers make.
///
/// The rendered text can show *what* was printed; it cannot show the contract
/// the printers keep with a rich target — whether every pushed scope is popped,
/// which writes sit under a barrier scope, which semantic state a write carries,
/// and whether a memoized fragment was spliced in through `append`. This target
/// records those as events so a test can assert on them directly. Being a
/// second `Target` next to `SemanticString`, it also keeps the printers honest
/// about their generic parameter.
struct RecordingPrinterTarget: NodePrinterTarget {
    enum Scope: Equatable, Sendable {
        /// No `pushTypeReferenceScope` is open.
        case none
        /// `pushTypeReferenceScope(nil)`: writes belong to no type reference.
        case barrier
        /// Writes belong to the type reference rooted at this node.
        case typeReference(ObjectIdentifier)
    }

    enum Event: Equatable, Sendable {
        case write(String, state: NodePrintState?, parentKind: Node.Kind?, scope: Scope)
        case pushScope(Scope)
        case popScope
        case append(writtenUnitCount: Int)
    }

    private(set) var events: [Event] = []

    private(set) var text = ""

    /// Pops that found no open scope; a printer that pops more than it pushes
    /// would otherwise go unnoticed, because popping an empty stack is a no-op
    /// on the real targets.
    private(set) var unbalancedPopCount = 0

    private var scopeStack: [Scope] = []

    init() {}

    var writtenUnitCount: Int { text.utf8.count }

    var writes: [Event] {
        events.filter { if case .write = $0 { true } else { false } }
    }

    var pushCount: Int {
        events.filter { if case .pushScope = $0 { true } else { false } }.count
    }

    var popCount: Int {
        events.filter { if case .popScope = $0 { true } else { false } }.count
    }

    var appendCount: Int {
        events.filter { if case .append = $0 { true } else { false } }.count
    }

    private var innermostScope: Scope { scopeStack.last ?? .none }

    mutating func write(_ content: String) {
        text += content
        events.append(.write(content, state: nil, parentKind: nil, scope: innermostScope))
    }

    mutating func write(_ content: String, context: @autoclosure () -> NodePrintContext?) {
        text += content
        let context = context()
        events.append(.write(content, state: context?.state, parentKind: context?.parentKind, scope: innermostScope))
    }

    /// Splices a memoized fragment in. The printers render every cacheable
    /// subtree into a fresh target and append it, so a target that copied only
    /// the text here would lose every event under such a subtree — which is
    /// exactly what `NodePrinterTarget` warns `append` must not do. The fragment's
    /// events keep the scopes they were written under: those are the fragment's
    /// own pushes, which is what a rich target attributes them to as well.
    mutating func append(_ other: RecordingPrinterTarget) {
        text += other.text
        events.append(.append(writtenUnitCount: other.writtenUnitCount))
        events.append(contentsOf: other.events)
        unbalancedPopCount += other.unbalancedPopCount
    }

    mutating func pushTypeReferenceScope(_ node: @autoclosure () -> Node?) {
        let scope: Scope = node().map { .typeReference(ObjectIdentifier($0)) } ?? .barrier
        scopeStack.append(scope)
        events.append(.pushScope(scope))
    }

    mutating func popTypeReferenceScope() {
        if scopeStack.popLast() == nil {
            unbalancedPopCount += 1
        }
        events.append(.popScope)
    }
}

@Suite
struct RecordingPrinterTargetTests {
    /// `Main.Pair<Swift.Int, Swift.String>`: an unsugared bound generic, so the
    /// angle brackets and the comma are the printer's own punctuation.
    private static let boundGenericPairMangling = "$s4Main4PairVySiSSG"

    /// `static Main.Cls.foo()`.
    private static let staticMethodMangling = "$s4Main3ClsC3fooyyFZ"

    private func typeNode(_ mangled: String) async throws -> Node {
        let node = try await demangleAsNode(mangled)
        return try #require(node.children.first)
    }

    @Test
    func plainStringTargetRendersTheSameTextAsSemanticString() async throws {
        let node = try await typeNode(Self.boundGenericPairMangling)
        var plainPrinter = TypeNodePrinter<String>()
        var semanticPrinter = SemanticTypeNodePrinter()

        let plainText = try await plainPrinter.printRoot(node)
        let semanticText = try await semanticPrinter.printRoot(node).string

        #expect(plainText == "Main.Pair<Swift.Int, Swift.String>")
        #expect(plainText == semanticText)
    }

    @Test
    func plainStringTargetRendersTheSameDeclarationAsSemanticString() async throws {
        let node = try await demangleAsNode(Self.staticMethodMangling)
        var plainPrinter = FunctionNodePrinter<String>(isOverride: true, isClassMember: true, isFinal: true)
        var semanticPrinter = SemanticFunctionNodePrinter(isOverride: true, isClassMember: true, isFinal: true)

        let plainText = try await plainPrinter.printRoot(node)
        let semanticText = try await semanticPrinter.printRoot(node).string

        #expect(plainText == "final override class func foo()")
        #expect(plainText == semanticText)
    }

    @Test
    func everyTypeReferenceScopeIsPopped() async throws {
        let node = try await typeNode(Self.boundGenericPairMangling)
        var printer = TypeNodePrinter<RecordingPrinterTarget>()

        let target = try await printer.printRoot(node)

        #expect(target.text == "Main.Pair<Swift.Int, Swift.String>")
        #expect(target.pushCount == target.popCount)
        #expect(target.unbalancedPopCount == 0)
        #expect(target.pushCount > 0, "a bound generic opens a scope per nominal reference plus one barrier")
    }

    /// Every cacheable `printName` renders into a fresh sub-target and splices it
    /// back through `append`; a type print therefore exercises that path even
    /// when no node is shared. A target that dropped events on `append` would
    /// see none of the scopes below — the first version of this file did.
    @Test
    func memoizedSubtreesAreSplicedThroughAppend() async throws {
        let node = try await typeNode(Self.boundGenericPairMangling)
        var printer = TypeNodePrinter<RecordingPrinterTarget>()

        let target = try await printer.printRoot(node)

        #expect(target.appendCount > 0)
        #expect(target.writes.count > target.appendCount, "the spliced fragments carry their writes")
    }

    @Test
    func boundGenericPunctuationIsWrittenUnderABarrierAndNamesUnderTheirNominal() async throws {
        let node = try await typeNode(Self.boundGenericPairMangling)
        var printer = TypeNodePrinter<RecordingPrinterTarget>()

        let target = try await printer.printRoot(node)

        let nonEmptyWrites = target.writes.filter { if case .write(let content, _, _, _) = $0 { !content.isEmpty } else { false } }
        #expect(nonEmptyWrites.count >= 9, "Main . Pair < Swift . Int , Swift . String >")
        for event in nonEmptyWrites {
            guard case .write(let content, _, _, let scope) = event else { continue }
            switch content {
            case "<", ", ", ">":
                #expect(scope == .barrier, "\(content.debugDescription) belongs to no type reference")
            case "Pair", "Int", "String", "Main", "Swift", ".":
                if case .typeReference = scope {
                    // The qualified name, its module and the module-to-type dot
                    // all sit inside the nominal reference's own scope.
                } else {
                    Issue.record("\(content.debugDescription) written under \(scope), expected a type reference scope")
                }
            default:
                Issue.record("unexpected write \(content.debugDescription)")
            }
        }
    }

    @Test
    func declarationKeywordsAndIdentifiersCarryTheirSemanticState() async throws {
        let node = try await demangleAsNode(Self.staticMethodMangling)
        var printer = FunctionNodePrinter<RecordingPrinterTarget>(isOverride: true, isClassMember: true, isFinal: true)

        let target = try await printer.printRoot(node)

        #expect(target.text == "final override class func foo()")
        let keywords = target.writes.compactMap { event -> String? in
            guard case .write(let content, .printKeyword, _, _) = event else { return nil }
            return content
        }
        #expect(keywords == ["final", "override", "class", "func"])
        #expect(target.writes.contains(.write("foo", state: .printIdentifier, parentKind: .function, scope: .none)))
    }
}
