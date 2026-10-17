import Foundation
import Testing
import MachOKit
@testable import CrossReferenceAnalysis

/// Where code takes a class object's address, the class a send goes to when
/// the code names it, and the class a super send starts above.
@Suite(.enabled(if: SharedAnalyzer.analyzer != nil, "needs an arm64 process with a dyld shared cache"))
struct ObjectiveCClassReferenceTests {
    private var analyzer: CrossReferenceAnalyzer { SharedAnalyzer.analyzer! }

    private func imageIndex(endingWith suffix: String) throws -> Int {
        try #require(analyzer.imagePaths.firstIndex { $0.hasSuffix(suffix) }, "no image ending with \(suffix)")
    }

    private func function(named name: String, inImageAt imageIndex: Int) throws -> CodeFunction {
        try #require(analyzer.functions(inImageAt: imageIndex).first { $0.name == .symbol(name) }, "no function \(name)")
    }

    private func classLocation(named name: String, inImageAt imageIndex: Int) throws -> CodeLocation {
        let locations = analyzer.objectiveCClassLocations(named: name, inImageAt: imageIndex)
        #expect(locations.count == 1)
        return try #require(locations.first, "\(analyzer.imagePaths[imageIndex]) defines no class \(name)")
    }

    /// macOS 27.2 reaches a class three ways, and AppKit uses all three:
    /// `adrp` / `add` of a class object of its own, a load from its own GOT,
    /// and a load from the GOT pool the shared cache keeps outside every
    /// image, for another image's class. A class's metaclass and every
    /// alias name lead to the same class.
    @Test func everyFormOfClassReferenceIsFound() throws {
        let appKit = try imageIndex(endingWith: "/AppKit.framework/Versions/C/AppKit")
        let foundation = try imageIndex(endingWith: "/Foundation.framework/Versions/C/Foundation")
        let string = try classLocation(named: "NSString", inImageAt: foundation)
        let slide = try #require(analyzer.images[appKit].vmaddrSlide)
        var forms = Set<String>()
        var classesLoadedFromElsewhere = Set<CodeLocation>()
        for reference in analyzer.referenceTable(ofImageAt: appKit).references {
            guard case .objectiveCClass(_, let location) = reference.target else { continue }
            #expect(reference.kind == .reference)
            let word = UnsafeRawPointer(bitPattern: Int(bitPattern: UInt(reference.instructionAddress)) &+ slide)!.load(as: UInt32.self)
            let form = word & 0xFF80_0000 == 0x9100_0000 ? "add" : "load"
            forms.insert("\(form) of \(location.imageIndex == appKit ? "its own" : "another image's") class")
            if form == "load", location.imageIndex != appKit { classesLoadedFromElsewhere.insert(location) }
        }
        #expect(forms.isSuperset(of: ["add of its own class", "load of its own class", "load of another image's class"]))
        #expect(classesLoadedFromElsewhere.contains(string))
    }

    /// `[NSNotificationCenter _defaultCenterWithoutCreating]`, from an
    /// Objective-C method: the class is loaded right before the send.
    @Test func classLiteralReceiversNameTheirClass() throws {
        let foundation = try imageIndex(endingWith: "/Foundation.framework/Versions/C/Foundation")
        let method = try function(named: "+[NSThread currentThread]", inImageAt: foundation)
        let receivers = analyzer.references(madeBy: method).compactMap { reference -> ReceiverClassHint? in
            guard case .messageSend("_defaultCenterWithoutCreating", let receiver) = reference.target else { return nil }
            return receiver
        }
        #expect(receivers == [.classLiteral("NSNotificationCenter")])
    }

    /// Swift calls an Objective-C class method through `objc_opt_self`,
    /// which returns the class it was handed: `NSApplication.shared` loads
    /// the class, calls `objc_opt_self`, then sends `sharedApplication` to
    /// what came back. Forgetting `x0` across that call, as across any
    /// other, lost the class.
    @Test func classLiteralsSurviveObjcOptSelf() throws {
        let swiftUI = try imageIndex(endingWith: "/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI")
        let function = try function(named: "_$s7SwiftUI14_BenchmarkHostPAAE8_started4testyAA16_PerformanceTest_p_tF", inImageAt: swiftUI)
        let receivers = analyzer.references(madeBy: function).compactMap { reference -> ReceiverClassHint? in
            guard case .messageSend("sharedApplication", let receiver) = reference.target else { return nil }
            return receiver
        }
        #expect(receivers == [.classLiteral("NSApplication")])
    }

    /// A super send starts above the class its `__objc_superrefs` slot
    /// holds: the method's own class, a category's class included, and a
    /// class method's metaclass reported as its class.
    @Test(arguments: zip(
        ["-[NSDictionary(NSKeyValueCoding) valueForKey:]", "+[NSURL(NSURL) allocWithZone:]"],
        ["valueForKey:", "allocWithZone:"]
    ))
    func superSendsNameTheClassOfTheirMethod(method name: String, selector: String) throws {
        let foundation = try imageIndex(endingWith: "/Foundation.framework/Versions/C/Foundation")
        let method = try function(named: name, inImageAt: foundation)
        let className = String(name.dropFirst(2).prefix { $0 != "(" && $0 != " " })
        let superSends = analyzer.references(madeBy: method).filter {
            if case .superMessageSend(selector, className) = $0.target { return true }
            return false
        }
        #expect(!superSends.isEmpty)
        // The superrefs load itself is no reference to the class.
        #expect(!analyzer.references(madeBy: method).contains {
            if case .objectiveCClass = $0.target { return true }
            return false
        })
    }

    /// Where no symbol names the sending method, the superrefs slot still
    /// gives its class — the one the method lists put the method in.
    @Test func superSendsOfUnsymbolizedMethodsNameTheirClass() throws {
        let matter = try imageIndex(endingWith: "/Matter.framework/Versions/A/Matter")
        var compared = 0
        for function in analyzer.functions(inImageAt: matter) {
            guard case .objectiveCMethod(let methodClassName, _, _)? = function.name else { continue }
            for reference in analyzer.references(madeBy: function) {
                guard case .superMessageSend(_, let className) = reference.target else { continue }
                compared += 1
                #expect(className == methodClassName)
            }
            if compared >= 200 { break }
        }
        #expect(compared >= 200)
    }

    /// The macOS and the Mac Catalyst SwiftUI both define this class; each
    /// image's references lead to its own.
    @Test func referencesTellApartClassesOfTheSameName() throws {
        let name = "_TtC7SwiftUI13PinnedBarView"
        let macOS = try imageIndex(endingWith: "/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI")
        let catalyst = try #require(analyzer.imagePaths.firstIndex { $0.hasSuffix("/System/iOSSupport/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI") })
        for imageIndex in [macOS, catalyst] {
            let own = try classLocation(named: name, inImageAt: imageIndex)
            let locations = analyzer.references(to: [.objectiveCClass(name)], inImageAt: imageIndex).compactMap { reference -> CodeLocation? in
                guard case .objectiveCClass(name, let location) = reference.target else { return nil }
                return location
            }
            #expect(!locations.isEmpty)
            #expect(Set(locations) == [own])
        }
    }

    /// A class prefilter may drop only images that cannot reference the
    /// class. Most images reach another image's class as
    /// `_OBJC_CLASS_$_<name>`; a block literal's `isa`
    /// (`__NSConcreteStackBlock`) and an XPC type (`__xpc_type_dictionary`)
    /// are reached under other names.
    ///
    /// The dropped images are sampled, every sixteenth: a Debug build scans
    /// the whole cache in minutes, not seconds.
    @Test(arguments: zip(
        ["/AppKit.framework/Versions/C/AppKit", "/Foundation.framework/Versions/C/Foundation", "/usr/lib/system/libsystem_blocks.dylib", "/usr/lib/system/libxpc.dylib"],
        ["NSWindow", "NSUUID", "__NSStackBlock__", "OS_xpc_dictionary"]
    ))
    func classPrefilterKeepsEveryReferencingImage(imageSuffix: String, className: String) throws {
        let owner = try imageIndex(endingWith: imageSuffix)
        let location = try classLocation(named: className, inImageAt: owner)
        let everyImage = Array(analyzer.images.indices)
        let kept = analyzer.imageIndices(referencingObjectiveCClassAt: location, among: everyImage)
        #expect(kept.contains(owner))
        let importers = kept.filter { $0 != owner }
        #expect(!imagesReferencing(className, at: location, among: Array(importers.prefix(64))).isEmpty)
        let droppedSample = Self.sample(of: Set(everyImage).subtracting(kept))
        let missed = imagesReferencing(className, at: location, among: droppedSample)
        #expect(missed.isEmpty, "prefilter dropped referencing images: \(missed.sorted().prefix(5).map { analyzer.imagePaths[$0] })")
    }

    /// Every sixteenth of `imageIndices`, in order.
    private static func sample(of imageIndices: Set<Int>) -> [Int] {
        imageIndices.sorted().enumerated().filter { $0.offset % 16 == 0 }.map(\.element)
    }

    /// The images among `imageIndices` that reference the class at `location`.
    private func imagesReferencing(_ className: String, at location: CodeLocation, among imageIndices: [Int]) -> Set<Int> {
        let found = ImageIndexCollector()
        let analyzer = analyzer
        DispatchQueue.concurrentPerform(iterations: imageIndices.count) { position in
            let imageIndex = imageIndices[position]
            let references = analyzer.references(to: [.objectiveCClass(className)], inImageAt: imageIndex)
            if references.contains(where: { $0.target == .objectiveCClass(name: className, location: location) }) { found.insert(imageIndex) }
        }
        return found.indices
    }
}
