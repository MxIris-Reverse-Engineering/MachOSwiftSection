import Dispatch
import SwiftStdlibToolbox

package final class MemoryPressureMonitor: Sendable {
    private let queue = DispatchQueue(label: "com.JH.MemoryPressureMonitorQueue")

    @Mutex
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    @Mutex
    package var memoryWarningHandler: (() -> Void)?

    @Mutex
    package var memoryCriticalHandler: (() -> Void)?

    package init() {}

    package func startMonitoring() {
        guard memoryPressureSource == nil else { return }

        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: queue)

        source.setEventHandler { [weak self] in
            guard let self = self else { return }

            let event = source.data

            if event.contains(.warning) {
                self.handleMemoryWarning()
            }
            if event.contains(.critical) {
                self.handleMemoryCritical()
            }
        }

        memoryPressureSource = source

        source.resume()
    }

    package func stopMonitoring() {
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
    }

    private func handleMemoryWarning() {
        memoryWarningHandler?()
    }

    private func handleMemoryCritical() {
        memoryCriticalHandler?()
    }

    deinit {
        stopMonitoring()
    }
}
