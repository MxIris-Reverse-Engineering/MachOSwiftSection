import Dispatch

class MemoryPressureMonitor {

    private var memoryPressureSource: DispatchSourceMemoryPressure?
    
    private let queue = DispatchQueue(label: "com.JH.MemoryPressureMonitorQueue")

    var memoryWarningHandler: (() -> Void)?
    
    var memoryCriticalHandler: (() -> Void)?
    
    func startMonitoring() {
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

        self.memoryPressureSource = source
        
        source.resume()
    }

    func stopMonitoring() {
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
