/// A macro that provides thread-safe access using Swift's Mutex.
///
/// When applied to a property:
/// ```swift
/// @Mutex
/// var counter: Int = 0
/// ```
///
/// When applied to a type:
/// ```swift
/// @Mutex
/// struct SharedState {
///     var counter: Int = 0
///     var message: String = ""
/// }
/// ```
@attached(peer, names: prefixed(_))
@attached(accessor)
//@attached(member, names: arbitrary)
public macro Mutex() = #externalMacro(
    module: "MachOMacroPlugin",
    type: "MutexMacro"
)

/// A generic weak reference container for thread-safe weak properties
public struct WeakBox<T: AnyObject> {
    public weak var value: T?
    
    public init(_ value: T? = nil) {
        self.value = value
    }
}
