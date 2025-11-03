import Foundation
import Network
import Combine

/// Monitors network connectivity and publishes connection status
/// Uses debouncing to prevent UI flickering on spotty signal
class NetworkMonitor: ObservableObject {
    @Published var isConnected = true
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private var cancellables = Set<AnyCancellable>()
    
    // Internal subject to handle raw path updates
    private let pathStatusSubject = PassthroughSubject<NWPath.Status, Never>()
    
    init() {
        print("⏱️ [NetworkMonitor] init() started")
        // Set up Combine pipeline with debounce
        pathStatusSubject
            .map { $0 == .satisfied }
            .removeDuplicates()
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .assign(to: &$isConnected)
        
        // Start monitoring network path changes
        monitor.pathUpdateHandler = { [weak self] path in
            self?.pathStatusSubject.send(path.status)
        }
        monitor.start(queue: queue)
        print("✅ [NetworkMonitor] init() completed")
    }
    
    deinit {
        monitor.cancel()
    }
}

