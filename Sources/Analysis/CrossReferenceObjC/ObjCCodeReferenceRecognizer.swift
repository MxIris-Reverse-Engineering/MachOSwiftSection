import Foundation
import MachOKit
import CrossReferenceCore

/// Where the references only the Objective-C layer recognizes go.
package protocol ObjCCodeReferenceRecording: CodeReferenceRecording {
    func recordMessageSend(selector: String, receiver: ReceiverClassHint, at site: ScanSite)
    /// `className`: the class the lookup starts above, or `nil` when the
    /// sending code builds its `objc_super` from a class known only at run
    /// time.
    func recordSuperMessageSend(selector: String, className: String?, at site: ScanSite)
    func recordClassReference(_ classObject: ObjectiveCClassObject, at site: ScanSite)
    /// A load of an instance variable's offset variable.
    func recordInstanceVariableReference(className: String, name: String, at site: ScanSite)
}

/// What a runtime function returns of the class it is handed in `x0`.
package enum ClassArgumentReturn: Hashable, Sendable {
    /// `objc_opt_self`, `swift_getInitializedObjCClass`: the argument
    /// itself, whatever it is.
    case argument
    /// `objc_opt_class`: the argument's class — the argument itself only
    /// when it is a class object. An instance method's `[self class]` is
    /// the receiver's class, not the receiver.
    case classOfArgument
}

/// libobjc's functions a scan recognizes by name, collected from the runtime
/// libraries' symbols when an analyzer is built.
package struct ObjCRuntimeFunctions: Sendable {
    /// Where `objc_msgSend` lives, the original and the copies the cache
    /// carries for its shared selector stubs.
    package private(set) var messageSendLocations = Set<CodeLocation>()
    package private(set) var superMessageSendLocations = Set<CodeLocation>()
    /// libobjc's entry points that stand for sends — `objc_alloc_init`,
    /// `objc_opt_isKindOfClass` … — and the selectors each sends
    /// (`MessageSendEntryPoints`).
    package private(set) var messageSendEntryPoints: [CodeLocation: [String]] = [:]
    /// `objc_opt_self` and `objc_opt_class`, and what each returns of the
    /// class it is handed.
    package private(set) var classReturningFunctions: [CodeLocation: ClassArgumentReturn] = [:]

    package init() {}

    /// Notes the runtime library symbol `name` at `location` when it is one
    /// of libobjc's.
    package mutating func consider(_ name: UnsafePointer<CChar>, at location: CodeLocation) {
        if strcmp(name, "_objc_msgSend") == 0 {
            messageSendLocations.insert(location)
        } else if strcmp(name, "_objc_msgSendSuper2") == 0 {
            superMessageSendLocations.insert(location)
        } else if let selectors = MessageSendEntryPoints.selectors(ofSymbol: name) {
            messageSendEntryPoints[location] = selectors
            if let classArgumentReturn = Self.classArgumentReturn(name) { classReturningFunctions[location] = classArgumentReturn }
        } else if let classArgumentReturn = Self.classArgumentReturn(name) {
            classReturningFunctions[location] = classArgumentReturn
        }
    }

    /// `objc_opt_self`, `objc_opt_class`: what each returns of the class it
    /// is handed; `nil` for any other.
    package static func classArgumentReturn(_ name: UnsafePointer<CChar>) -> ClassArgumentReturn? {
        if strcmp(name, "_objc_opt_self") == 0 { return .argument }
        if strcmp(name, "_objc_opt_class") == 0 { return .classOfArgument }
        return nil
    }

    /// The libraries whose exported functions the layer recognizes, and
    /// whose `objc_msgSend` copies the shared selector stubs branch to.
    package static func isRuntimeLibrary(_ path: String) -> Bool {
        path.hasSuffix("/libobjc.A.dylib") || path.contains("/libobjcMsgSend")
    }
}

/// The Objective-C layer of the cross-reference analysis: message sends —
/// through `objc_msgSend`, a selector stub, or one of libobjc's entry points
/// that stand for sends — super sends, class references, and the receivers
/// sends start from. Evolution proposals `cross-reference-analysis`,
/// `objc-runtime-send-entry-points`, `offline-cross-references-and-symbolication`.
///
/// Keeps every image's class index it was asked for, like the core keeps
/// function tables: a scan meets the same few hundred classes again and
/// again.
package final class ObjCCodeReferenceRecognizer: @unchecked Sendable {
    package let images: CodeImageSet
    package let runtimeFunctions: ObjCRuntimeFunctions
    private let lock = NSLock()
    private var classIndexes: [Int: ObjectiveCClassIndex] = [:]

    package init(images: CodeImageSet, runtimeFunctions: ObjCRuntimeFunctions) {
        self.images = images
        self.runtimeFunctions = runtimeFunctions
    }

    /// A session for one scan of the image `table` covers. `findsClassReferences`:
    /// whether the scan looks for class references at all — a query for the
    /// callers of a selector keeps none; a send's class-literal receiver is
    /// still told, at the send.
    package func makeSession(table: ImageFunctionTable, recording: any ObjCCodeReferenceRecording, findsClassReferences: Bool) -> ObjCCodeReferenceRecognitionSession {
        ObjCCodeReferenceRecognitionSession(recognizer: self, table: table, recording: recording, findsClassReferences: findsClassReferences)
    }

    /// The image's class index, built on first use and then kept.
    package func classIndex(ofImageAt imageIndex: Int) -> ObjectiveCClassIndex {
        lock.lock()
        if let index = classIndexes[imageIndex] {
            lock.unlock()
            return index
        }
        lock.unlock()
        let index = ObjectiveCClassIndex(image: images.images[imageIndex], imageIndex: imageIndex, memory: images.memory)
        lock.lock()
        defer { lock.unlock() }
        if let stored = classIndexes[imageIndex] { return stored }
        classIndexes[imageIndex] = index
        return index
    }

    package func existingClassIndex(ofImageAt imageIndex: Int) -> ObjectiveCClassIndex? {
        lock.lock()
        defer { lock.unlock() }
        return classIndexes[imageIndex]
    }

    /// Drops the class indexes of every image but `keptImageIndices`, and
    /// returns them so that the caller frees them outside any lock.
    package func releaseClassIndexes(exceptForImagesAt keptImageIndices: Set<Int>) -> [Int: ObjectiveCClassIndex] {
        lock.lock()
        defer { lock.unlock() }
        let released = classIndexes
        classIndexes = classIndexes.filter { keptImageIndices.contains($0.key) }
        return released
    }

    /// The class object at the runtime `address`, when an image lists one
    /// there; a metaclass is reported as its class.
    package func classObject(atRuntimeAddress address: UInt) -> ObjectiveCClassObject? {
        guard let imageIndex = images.imageIndex(containingDataAddress: address) else { return nil }
        return classIndex(ofImageAt: imageIndex).classObject(atRuntimeAddress: address)
    }

    /// The methods the image's function table names, read now; for a host
    /// preparing an image's names.
    package func readMethodNames(of table: ImageFunctionTable) {
        _ = ObjCMethodNames.of(table)
    }
}

/// One scan of one image by the Objective-C layer, on one thread.
package final class ObjCCodeReferenceRecognitionSession: CodeReferenceRecognitionSession {
    /// The tag the session puts on `x0` when an Objective-C method starts: it
    /// holds the receiver.
    static let methodReceiverTag: UInt64 = 1

    private let recognizer: ObjCCodeReferenceRecognizer
    private let images: CodeImageSet
    private let table: ImageFunctionTable
    private let sections: ObjCImageSections
    private let recording: any ObjCCodeReferenceRecording
    private let findsClassReferences: Bool
    /// The image's GOT and class references: the slots a receiver may come
    /// from.
    private let ownReferenceSlotRanges: [Range<UInt64>]

    /// What each role code stands for: role `n` is `rolePlans[n - 1]`.
    private enum RolePlan {
        /// A call to `objc_msgSend`: a send when `x1` says which selector.
        case classicSend
        /// A call to `objc_msgSendSuper2`.
        case superSend
        /// A stub that names its selector.
        case selector(UnsafePointer<CChar>)
        /// A libobjc entry point that stands for these sends, the first to
        /// the receiver in `x0`.
        case entryPoint(selectors: [String], classArgumentReturn: ClassArgumentReturn?)
    }

    @exclusivity(unchecked)
    private var rolePlans: [RolePlan] = []
    @exclusivity(unchecked)
    private var classIndexes: [Int: ObjectiveCClassIndex] = [:]
    @exclusivity(unchecked)
    private var classObjects: [UInt: ObjectiveCClassObject?] = [:]
    @exclusivity(unchecked)
    private var selectorNames: [UInt: String] = [:]
    @exclusivity(unchecked)
    private var currentFunctionIndex = 0
    @exclusivity(unchecked)
    private var isObjectiveCMethod = false
    @exclusivity(unchecked)
    private var isObjectiveCClassMethod = false
    /// The class the current function's last load from `__objc_superrefs`
    /// yielded: a super send in it starts above that class.
    @exclusivity(unchecked)
    private var superclassReferenceClassName: String?

    init(recognizer: ObjCCodeReferenceRecognizer, table: ImageFunctionTable, recording: any ObjCCodeReferenceRecording, findsClassReferences: Bool) {
        self.recognizer = recognizer
        self.images = recognizer.images
        self.table = table
        self.sections = ObjCImageSections.of(table)
        self.recording = recording
        self.findsClassReferences = findsClassReferences
        self.ownReferenceSlotRanges = table.globalOffsetTableRanges + sections.classReferenceRanges
    }

    package var referenceSlotRanges: [Range<UInt64>] { sections.classReferenceRanges }

    package var watchedSlotRanges: [Range<UInt64>] {
        [sections.superclassReferenceRange, findsClassReferences ? sections.instanceVariableOffsetRange : nil].compactMap(\.self)
    }

    package var looksForAddressReferences: Bool { findsClassReferences }

    package func enterFunction(at functionIndex: Int, registers: RegisterFile) {
        currentFunctionIndex = functionIndex
        superclassReferenceClassName = nil
        isObjectiveCMethod = false
        isObjectiveCClassMethod = false
        guard let name = table.primaryName(ofFunctionAt: functionIndex) else { return }
        isObjectiveCMethod = (name[0] == 0x2D || name[0] == 0x2B) && name[1] == 0x5B
        isObjectiveCClassMethod = name[0] == 0x2B && name[1] == 0x5B
        if isObjectiveCMethod { registers.setTag(Self.methodReceiverTag, of: 0) }
    }

    // MARK: - Calls

    package func claimCallTarget(at target: UInt64) -> CallTargetClaim? {
        guard let range = sections.stubRange, range.contains(target) else { return nil }
        guard let selector = sections.stubSelectors[target] else { return .unrecognized }
        return .role(addRole(.selector(selector)))
    }

    package func role(of target: ResolvedCallTarget) -> CalleeRole? {
        let functions = recognizer.runtimeFunctions
        switch target {
        case .function(let location):
            if functions.messageSendLocations.contains(location) { return addRole(.classicSend) }
            if functions.superMessageSendLocations.contains(location) { return addRole(.superSend) }
            if let selectors = functions.messageSendEntryPoints[location] {
                return addRole(.entryPoint(selectors: selectors, classArgumentReturn: functions.classReturningFunctions[location]))
            }
            return nil
        case .importedSymbol(let name):
            // libobjc reached by name: a standalone app analyzed without it.
            if strcmp(name, "_objc_msgSend") == 0 { return addRole(.classicSend) }
            if strcmp(name, "_objc_msgSendSuper2") == 0 { return addRole(.superSend) }
            guard let selectors = MessageSendEntryPoints.selectors(ofSymbol: name) else { return nil }
            return addRole(.entryPoint(selectors: selectors, classArgumentReturn: ObjCRuntimeFunctions.classArgumentReturn(name)))
        case .registerSettingTrampoline(let register, let value):
            // A cache-shared selector stub: `x1` holds the selector string.
            guard register == 1, value != 0, images.isMapped(runtimeAddress: UInt(value), length: 1),
                  let selector = images.memory.typedPointer(to: CChar.self, at: UInt(value), length: 1)
            else { return nil }
            return addRole(.selector(selector))
        case .unrecognized:
            return nil
        }
    }

    /// Every role stands in for the call — it is a send; an entry point that
    /// returns its class argument also keeps `x0` after it.
    private func addRole(_ plan: RolePlan) -> CalleeRole {
        rolePlans.append(plan)
        var keepsClassArgument = false
        if case .entryPoint(_, let classArgumentReturn) = plan { keepsClassArgument = classArgumentReturn != nil }
        return CalleeRole(code: UInt32(rolePlans.count), mayStandIn: true, notesCallMade: keepsClassArgument)
    }

    package func recordCallStandIn(_ call: ScannedCall, registers: RegisterFile) -> Bool {
        switch rolePlans[Int(call.role) - 1] {
        case .classicSend:
            guard let selector = selectorInSelectorRegister(registers) else { return false }
            recording.recordMessageSend(selector: selector, receiver: receiverHint(registers), at: call.site)
        case .superSend:
            guard let selector = selectorInSelectorRegister(registers) else { return false }
            recording.recordSuperMessageSend(selector: selector, className: superclassSendClassName(), at: call.site)
        case .selector(let selector):
            recording.recordMessageSend(selector: selectorName(selector), receiver: receiverHint(registers), at: call.site)
        case .entryPoint(let selectors, _):
            // The later sends go to what the one before returned, which the
            // scan does not know.
            recording.recordMessageSend(selector: selectors[0], receiver: receiverHint(registers), at: call.site)
            for selector in selectors.dropFirst() {
                recording.recordMessageSend(selector: selector, receiver: .unknown, at: call.site)
            }
        }
        return true
    }

    package func noteCallMade(_ call: ScannedCall, registers: RegisterFile) -> UInt32 {
        guard case .entryPoint(_, let classArgumentReturn?) = rolePlans[Int(call.role) - 1] else { return 0 }
        switch classArgumentReturn {
        case .argument:
            return 1
        // A class object's class is itself; an instance method's receiver is
        // an instance, whose class is not what `x0` named.
        case .classOfArgument:
            return isObjectiveCClassMethod || registers.tag(of: 0) != Self.methodReceiverTag ? 1 : 0
        }
    }

    // MARK: - Class references

    package func recordAddressReference(toRuntimeAddress address: UInt, isCode: Bool, at site: ScanSite) -> Bool {
        guard findsClassReferences, !isCode, let classObject = classObject(atRuntimeAddress: address) else { return false }
        recording.recordClassReference(classObject, at: site)
        return true
    }

    package func recordSlotReference(holding value: UInt, at site: ScanSite) -> Bool {
        guard findsClassReferences, let classObject = classObject(atRuntimeAddress: value) else { return false }
        recording.recordClassReference(classObject, at: site)
        return true
    }

    package func noteWatchedSlotLoad(from slot: UInt64, at site: ScanSite) {
        if let instanceVariables = sections.instanceVariableOffsetRange, instanceVariables.contains(slot) {
            if let variable = ObjCInstanceVariableNames.of(table).instanceVariablesBySlot[slot] {
                recording.recordInstanceVariableReference(className: variable.className, name: variable.name, at: site)
            }
            return
        }
        let runtimeSlot = table.runtimeAddress(ofUnslid: slot)
        guard runtimeSlot != 0, let classAddress = images.memory.pointer(at: runtimeSlot) else {
            superclassReferenceClassName = nil
            return
        }
        superclassReferenceClassName = classObject(atRuntimeAddress: classAddress)?.name
    }

    private func classObject(atRuntimeAddress address: UInt) -> ObjectiveCClassObject? {
        if let known = classObjects[address] { return known }
        var classObject: ObjectiveCClassObject?
        if let imageIndex = images.imageIndex(containingDataAddress: address) {
            classObject = classIndex(ofImageAt: imageIndex).classObject(atRuntimeAddress: address)
        }
        classObjects[address] = classObject
        return classObject
    }

    /// The class indexes this scan asked for, kept here so that a lookup does
    /// not contend for the recognizer's lock — a whole-cache scan spent most
    /// of its time waiting on it.
    private func classIndex(ofImageAt imageIndex: Int) -> ObjectiveCClassIndex {
        if let index = classIndexes[imageIndex] { return index }
        let index = recognizer.classIndex(ofImageAt: imageIndex)
        classIndexes[imageIndex] = index
        return index
    }

    // MARK: - Receivers and selectors

    private func receiverHint(_ registers: RegisterFile) -> ReceiverClassHint {
        if isObjectiveCMethod, registers.tag(of: 0) == Self.methodReceiverTag { return .methodReceiver }
        if let classObject = classObject(inRegister: 0, registers) { return .classLiteral(classObject.name) }
        return .unknown
    }

    /// The class object a register holds: an `adrp` / `add` of the object,
    /// or a load from a reference slot holding it.
    private func classObject(inRegister register: Int, _ registers: RegisterFile) -> ObjectiveCClassObject? {
        if let address = registers.builtAddress(of: register) {
            // Code and the image's own constants hold no class object.
            if address >= table.textStart, address < table.textEnd { return nil }
            if !table.dataSegmentRanges.contains(where: { $0.contains(address) }), table.segmentRanges.contains(where: { $0.contains(address) }) { return nil }
            return classObject(atRuntimeAddress: table.runtimeAddress(ofUnslid: address))
        }
        if let slot = registers.slotAddress(of: register) {
            let isOwnReferenceSlot = ownReferenceSlotRanges.contains { $0.contains(slot) }
            if !isOwnReferenceSlot, table.segmentRanges.contains(where: { $0.contains(slot) }) { return nil }
            let runtimeSlot = table.runtimeAddress(ofUnslid: slot)
            guard isOwnReferenceSlot || images.isSlotOutsideEveryImage(runtimeAddress: runtimeSlot), runtimeSlot != 0,
                  let value = images.memory.pointer(at: runtimeSlot)
            else { return nil }
            return classObject(atRuntimeAddress: value)
        }
        return nil
    }

    /// The class a super send in the current function starts above: the one
    /// its `__objc_superrefs` slot holds — a category method's class too —
    /// or, when no such load was seen, the class its symbol names.
    private func superclassSendClassName() -> String? {
        superclassReferenceClassName ?? table.primaryName(ofFunctionAt: currentFunctionIndex).flatMap(Self.className(ofMethodSymbol:))
    }

    /// `-[NSView(NSLayout) frame]` → `NSView`.
    private static func className(ofMethodSymbol symbol: UnsafePointer<CChar>) -> String? {
        guard symbol[0] == 0x2D || symbol[0] == 0x2B, symbol[1] == 0x5B else { return nil }
        var length = 0
        while symbol[2 + length] != 0, symbol[2 + length] != 0x20, symbol[2 + length] != 0x28 { length += 1 }
        guard length > 0 else { return nil }
        return String(decoding: UnsafeRawBufferPointer(start: symbol + 2, count: length), as: UTF8.self)
    }

    /// The selector a classic send passes in `x1`: loaded from this image's
    /// selector references, or the selector string's own address.
    ///
    /// The second is what a classic send looks like inside the shared cache.
    /// The cache builder rewrites the `adrp` / `ldr` of a selector reference
    /// into an `adrp` / `add` of the string it points at, so the instructions
    /// carry only the string's address — macOS 27.2 compiles
    /// `-[NSObject debugDescription]` to `adrp x8; add x1, x8; b _objc_msgSend`.
    private func selectorInSelectorRegister(_ registers: RegisterFile) -> String? {
        if let slotAddress = registers.slotAddress(of: 1) {
            guard let range = sections.selectorReferenceRange, range.contains(slotAddress),
                  let selector = ObjCImageSections.selectorString(inSlotAt: slotAddress, of: table)
            else { return nil }
            return selectorName(selector)
        }
        if let stringAddress = registers.builtAddress(of: 1),
           let selector = selectorString(atRuntimeAddress: table.runtimeAddress(ofUnslid: stringAddress)) {
            return selectorName(selector)
        }
        return nil
    }

    /// The longest selector read; longer ones are taken for something else.
    private static let maximumSelectorLength = 1024

    /// A selector string at `address`: mapped, and printable up to its
    /// terminator. Checked rather than assumed — `x1` holds the selector by
    /// convention only, and a string runs to wherever its terminator is.
    private func selectorString(atRuntimeAddress address: UInt) -> UnsafePointer<CChar>? {
        let readableLength = min(images.mappedLength(fromRuntimeAddress: address), UInt(Self.maximumSelectorLength))
        guard readableLength > 0, address != 0, let bytes = images.memory.typedPointer(to: UInt8.self, at: address, length: Int(readableLength)) else { return nil }
        for index in 0 ..< Int(readableLength) {
            let byte = bytes[index]
            if byte == 0 {
                return index > 0 ? UnsafeRawPointer(bytes).assumingMemoryBound(to: CChar.self) : nil
            }
            // Selectors are identifiers and colons: printable, never a space.
            guard byte > 0x20, byte < 0x7F else { return nil }
        }
        return nil
    }

    private func selectorName(_ pointer: UnsafePointer<CChar>) -> String {
        let key = UInt(bitPattern: pointer)
        if let known = selectorNames[key] { return known }
        let name = String(cString: pointer)
        selectorNames[key] = name
        return name
    }
}
