import Foundation
import Testing
@testable import CrossReferenceAnalysis
@_spi(Internals) import MachOCodeReferences
@_spi(Internals) import ObjCCodeReferences

/// `[self class]` compiles to `objc_opt_class(self)`, which returns the class
/// of what it is handed: a class object itself, an instance's class
/// otherwise. In an instance method the send that follows goes to the
/// receiver's class, not to the receiver — a class method of it — so `x0` no
/// longer names the method's receiver; in a class method, and for a class
/// literal, it still names what it named.
@Suite(.enabled(if: SharedAnalyzer.analyzer != nil, "needs an arm64 process with a dyld shared cache"))
struct ClassOfReceiverSendTests {
    private struct Fixture {
        let analyzer: CrossReferenceAnalyzer
        let imageIndex: Int
    }

    /// The library is loaded before the analyzer that reads it is made.
    private static let fixture = Result<Fixture, any Error> {
        // Without ARC, so no call the compiler adds stands among them.
        try CompiledFixture.load(
            named: "CrossReferenceClassOfReceiver",
            sources: [
                "ClassOfReceiver.m": """
                #import <Foundation/Foundation.h>

                @interface CrossReferenceClassOfReceiverProbe : NSObject
                + (void)classSideProbe;
                - (void)sendsToItsClass;
                + (void)classSendsToItsClass;
                @end

                @implementation CrossReferenceClassOfReceiverProbe
                + (void)classSideProbe {}

                - (void)sendsToItsClass {
                    [[self class] classSideProbe];
                }

                + (void)classSendsToItsClass {
                    [[self class] classSideProbe];
                }
                @end

                void crossReferenceSendsToALiteralsClass(void) {
                    [[CrossReferenceClassOfReceiverProbe class] classSideProbe];
                }
                """,
            ],
            compilerArguments: ["-O1", "-mmacosx-version-min=12.0", "-fno-objc-arc", "-framework", "Foundation"]
        )
        guard let analyzer = CrossReferenceAnalyzer(),
              let imageIndex = analyzer.imagePaths.firstIndex(where: { $0.hasSuffix("/libCrossReferenceClassOfReceiver.dylib") })
        else { throw CompiledFixture.Failure(description: "the analyzer does not see the fixture") }
        return Fixture(analyzer: analyzer, imageIndex: imageIndex)
    }

    static let probe = ReceiverClassHint.classLiteral("CrossReferenceClassOfReceiverProbe")

    @Test(arguments: [
        // The instance's class is not the instance.
        ("-[CrossReferenceClassOfReceiverProbe sendsToItsClass]", [ClassOfReceiverSendTests.send("class", to: .methodReceiver), ClassOfReceiverSendTests.send("classSideProbe", to: .unknown)]),
        // A class object's class is the class object.
        ("+[CrossReferenceClassOfReceiverProbe classSendsToItsClass]", [ClassOfReceiverSendTests.send("class", to: .methodReceiver), ClassOfReceiverSendTests.send("classSideProbe", to: .methodReceiver)]),
        ("_crossReferenceSendsToALiteralsClass", [ClassOfReceiverSendTests.send("class", to: ClassOfReceiverSendTests.probe), ClassOfReceiverSendTests.send("classSideProbe", to: ClassOfReceiverSendTests.probe)]),
    ])
    func aSendAfterAskingForTheClassGoesToTheClassOfTheReceiver(functionName: String, expectedSends: [CodeReferenceTarget]) throws {
        let fixture = try Self.fixture.get()
        let function = try #require(fixture.analyzer.functions(inImageAt: fixture.imageIndex).first { $0.name == .symbol(functionName) }, "no function \(functionName)")
        let sends = fixture.analyzer.references(madeBy: function).filter { if case .messageSend = $0.target { true } else { false } }
        #expect(sends.map(\.target) == expectedSends)
    }

    static func send(_ selector: String, to receiver: ReceiverClassHint) -> CodeReferenceTarget {
        .messageSend(selector: selector, receiver: receiver)
    }
}
