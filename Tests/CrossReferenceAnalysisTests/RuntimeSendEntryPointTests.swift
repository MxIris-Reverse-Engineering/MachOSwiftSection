import Foundation
import Testing
@testable import CrossReferenceAnalysis

/// clang compiles `[[Foo alloc] init]`, `[x isKindOfClass:c]` and six more
/// sends into calls to libobjc entry points of their own — `objc_alloc_init`,
/// `objc_opt_isKindOfClass` … — so a send of `init` need not pass through
/// `objc_msgSend` at all: macOS 26.6's AppKit calls `objc_alloc_init` 2,488
/// times against 720 sends of `init` by selector. Each such call is the send
/// it stands for. Evolution proposal `objc-runtime-send-entry-points`.
@Suite(.enabled(if: SharedAnalyzer.analyzer != nil, "needs an arm64 process with a dyld shared cache"))
struct RuntimeSendEntryPointTests {
    private struct Fixture {
        let analyzer: CrossReferenceAnalyzer
        let imageIndex: Int
    }

    /// The library is loaded before the analyzer that reads it is made.
    private static let fixture = Result<Fixture, any Error> {
        // Without ARC, so no call the compiler adds stands among them.
        try CompiledFixture.load(
            libraryName: "libCrossReferenceRuntimeSends.dylib",
            sources: [
                "Sends.m": """
                #import <Foundation/Foundation.h>

                @interface CrossReferenceRuntimeSendProbe : NSObject
                @end

                @implementation CrossReferenceRuntimeSendProbe
                @end

                id crossReferenceAllocatesAndInitializes(void) {
                    return [[CrossReferenceRuntimeSendProbe alloc] init];
                }

                id crossReferenceAllocates(void) {
                    return [CrossReferenceRuntimeSendProbe alloc];
                }

                id crossReferenceAllocatesWithZone(void) {
                    return [CrossReferenceRuntimeSendProbe allocWithZone:nil];
                }

                id crossReferenceMakesANewInstance(void) {
                    return [CrossReferenceRuntimeSendProbe new];
                }

                Class crossReferenceAsksForTheClass(id object) {
                    return [object class];
                }

                id crossReferenceAsksForSelf(id object) {
                    return [object self];
                }

                BOOL crossReferenceAsksIsKindOfClass(id object, Class aClass) {
                    return [object isKindOfClass:aClass];
                }

                BOOL crossReferenceAsksRespondsToSelector(id object, SEL selector) {
                    return [object respondsToSelector:selector];
                }
                """,
            ],
            compilerArguments: ["-O1", "-mmacosx-version-min=12.0", "-fno-objc-arc", "-framework", "Foundation"]
        )
        guard let analyzer = CrossReferenceAnalyzer(),
              let imageIndex = analyzer.imagePaths.firstIndex(where: { $0.hasSuffix("/libCrossReferenceRuntimeSends.dylib") })
        else { throw CompiledFixture.Failure(description: "the analyzer does not see the fixture") }
        return Fixture(analyzer: analyzer, imageIndex: imageIndex)
    }

    static let probe = ReceiverClassHint.classLiteral("CrossReferenceRuntimeSendProbe")

    @Test(arguments: [
        ("_crossReferenceAllocatesAndInitializes", [RuntimeSendEntryPointTests.send("alloc", to: RuntimeSendEntryPointTests.probe), RuntimeSendEntryPointTests.send("init", to: .unknown)]),
        ("_crossReferenceAllocates", [RuntimeSendEntryPointTests.send("alloc", to: RuntimeSendEntryPointTests.probe)]),
        ("_crossReferenceAllocatesWithZone", [RuntimeSendEntryPointTests.send("allocWithZone:", to: RuntimeSendEntryPointTests.probe)]),
        ("_crossReferenceMakesANewInstance", [RuntimeSendEntryPointTests.send("new", to: RuntimeSendEntryPointTests.probe)]),
        ("_crossReferenceAsksForTheClass", [RuntimeSendEntryPointTests.send("class", to: .unknown)]),
        ("_crossReferenceAsksForSelf", [RuntimeSendEntryPointTests.send("self", to: .unknown)]),
        ("_crossReferenceAsksIsKindOfClass", [RuntimeSendEntryPointTests.send("isKindOfClass:", to: .unknown)]),
        ("_crossReferenceAsksRespondsToSelector", [RuntimeSendEntryPointTests.send("respondsToSelector:", to: .unknown)]),
    ])
    func anEntryPointCallIsTheSendItStandsFor(functionName: String, expectedSends: [CodeReferenceTarget]) throws {
        let fixture = try Self.fixture.get()
        let function = try #require(fixture.analyzer.functions(inImageAt: fixture.imageIndex).first { $0.name == .symbol(functionName) }, "no function \(functionName)")
        let references = fixture.analyzer.references(madeBy: function)
        let sends = references.filter { if case .messageSend = $0.target { true } else { false } }
        #expect(sends.map(\.target) == expectedSends, "\(references.map(\.target))")
        // One call: both sends of `objc_alloc_init` are its instruction's.
        #expect(Set(sends.map(\.instructionAddress)).count == 1)
        // The call is the send, not also a call to libobjc.
        let libobjcCalls = references.filter { reference in
            guard case .function(let location) = reference.target else { return false }
            return fixture.analyzer.imagePaths[location.imageIndex].hasSuffix("/libobjc.A.dylib")
        }
        #expect(libobjcCalls.isEmpty, "\(libobjcCalls.map(\.target))")
    }

    /// The fixture sends `init`, `isKindOfClass:` and `new` only through
    /// entry points, so no selector reference names them; the images that
    /// import the entry points are kept all the same.
    @Test(arguments: ["init", "alloc", "allocWithZone:", "new", "class", "self", "isKindOfClass:", "respondsToSelector:"])
    func theSelectorPrefilterKeepsImagesSendingThroughEntryPoints(selector: String) throws {
        let fixture = try Self.fixture.get()
        #expect(fixture.analyzer.imageIndices(referencingSelector: selector, among: [fixture.imageIndex]) == [fixture.imageIndex])
    }

    static func send(_ selector: String, to receiver: ReceiverClassHint) -> CodeReferenceTarget {
        .messageSend(selector: selector, receiver: receiver)
    }
}
