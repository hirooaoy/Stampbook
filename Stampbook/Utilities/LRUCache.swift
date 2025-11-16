import Foundation

/// Least Recently Used (LRU) Cache
/// Automatically evicts oldest items when capacity is reached
/// Thread-safe for concurrent access
/// Uses array-based tracking (no circular references)
class LRUCache<Key: Hashable, Value> {
    private var cache: [Key: Value] = [:]
    private var accessOrder: [Key] = []
    private let capacity: Int
    private let lock = NSLock()
    
    /// Current number of items in cache
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return cache.count
    }
    
    init(capacity: Int) {
        self.capacity = capacity
    }
    
    /// Get value for key (marks as recently used)
    func get(_ key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        
        guard let value = cache[key] else {
            return nil
        }
        
        // Move to end (most recently used)
        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
        }
        accessOrder.append(key)
        
        return value
    }
    
    /// Set value for key (marks as recently used)
    func set(_ key: Key, _ value: Value) {
        lock.lock()
        defer { lock.unlock() }
        
        // Update or add value
        cache[key] = value
        
        // Update access order
        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
        }
        accessOrder.append(key)
        
        // Evict LRU if over capacity
        if cache.count > capacity {
            evictLRU()
        }
    }
    
    /// Remove value for key
    func remove(_ key: Key) {
        lock.lock()
        defer { lock.unlock() }
        
        cache.removeValue(forKey: key)
        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
        }
    }
    
    /// Remove all cached values
    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        
        cache.removeAll()
        accessOrder.removeAll()
    }
    
    /// Get all cached keys (for debugging)
    func allKeys() -> [Key] {
        lock.lock()
        defer { lock.unlock() }
        return Array(cache.keys)
    }
    
    // MARK: - Private Helpers
    
    private func evictLRU() {
        guard let lruKey = accessOrder.first else { return }
        
        cache.removeValue(forKey: lruKey)
        accessOrder.removeFirst()
        
        #if DEBUG
        print("🗑️ [LRUCache] Evicted: \(lruKey)")
        #endif
    }
}

