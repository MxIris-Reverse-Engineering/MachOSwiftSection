import Foundation

/// libobjc's entry points that stand for Objective-C sends. clang compiles
/// `[[Foo alloc] init]` to `objc_alloc_init(Foo)`, `[x isKindOfClass:c]` to
/// `objc_opt_isKindOfClass(x, c)` and six more alike, so a send of `init`
/// need not pass through `objc_msgSend` at all: macOS 26.6's AppKit calls
/// `objc_alloc_init` 2,488 times against 720 sends of `init` by selector.
/// The receiver arrives in `x0`, as for `objc_msgSend`. Evolution proposal
/// `objc-runtime-send-entry-points`.
///
/// `objc_retain`, `objc_release` and `objc_autorelease` are left out: the
/// calls ARC adds and a `[x retain]` written in source compile to the same
/// call, and they stay runtime helpers.
enum MessageSendEntryPoints {
    /// The sends each entry point stands for, in the order it makes them,
    /// by its symbol: `objc_alloc_init` sends `alloc`, then `init` to what
    /// `alloc` returned.
    static let selectorsBySymbol: [String: [String]] = [
        "_objc_alloc": ["alloc"],
        "_objc_allocWithZone": ["allocWithZone:"],
        "_objc_alloc_init": ["alloc", "init"],
        "_objc_opt_new": ["new"],
        "_objc_opt_self": ["self"],
        "_objc_opt_class": ["class"],
        "_objc_opt_isKindOfClass": ["isKindOfClass:"],
        "_objc_opt_respondsToSelector": ["respondsToSelector:"],
    ]

    /// The sends the symbol `name` stands for; `nil` for every other symbol.
    static func selectors(ofSymbol name: UnsafePointer<CChar>) -> [String]? {
        guard strncmp(name, "_objc_", 6) == 0 else { return nil }
        return selectorsBySymbol[String(cString: name)]
    }

    /// The entry points that send `selector`, by symbol.
    static func symbols(sending selector: String) -> [String] {
        selectorsBySymbol.filter { $0.value.contains(selector) }.map(\.key).sorted()
    }
}
