import Foundation

/// Least Recently Used (LRU) Cache
/// Automatically evicts oldest items when capacity is reached
/// Thread-safe for concurrent access
class LRUCache<Key: Hashable, Value> {
    private class Node {
        let key: Key
        var value: Value
        var prev: Node?
        var next: Node?
        
        init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }
    
    private var cache: [Key: Node] = [:]
    private var head: Node?
    private var tail: Node?
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
        
        guard let node = cache[key] else {
            return nil
        }
        
        // Move to front (most recently used)
        moveToFront(node)
        return node.value
    }
    
    /// Set value for key (marks as recently used)
    func set(_ key: Key, _ value: Value) {
        lock.lock()
        defer { lock.unlock() }
        
        if let existingNode = cache[key] {
            // Update existing node
            existingNode.value = value
            moveToFront(existingNode)
        } else {
            // Create new node
            let newNode = Node(key: key, value: value)
            cache[key] = newNode
            addToFront(newNode)
            
            // Evict LRU if over capacity
            if cache.count > capacity {
                evictLRU()
            }
        }
    }
    
    /// Remove value for key
    func remove(_ key: Key) {
        lock.lock()
        defer { lock.unlock() }
        
        guard let node = cache[key] else { return }
        removeNode(node)
        cache.removeValue(forKey: key)
    }
    
    /// Remove all cached values
    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        
        cache.removeAll()
        head = nil
        tail = nil
    }
    
    /// Get all cached keys (for debugging)
    func allKeys() -> [Key] {
        lock.lock()
        defer { lock.unlock() }
        return Array(cache.keys)
    }
    
    // MARK: - Private Helpers
    
    private func moveToFront(_ node: Node) {
        guard node !== head else { return }
        
        removeNode(node)
        addToFront(node)
    }
    
    private func addToFront(_ node: Node) {
        node.next = head
        node.prev = nil
        
        head?.prev = node
        head = node
        
        if tail == nil {
            tail = node
        }
    }
    
    private func removeNode(_ node: Node) {
        if node === head {
            head = node.next
        }
        if node === tail {
            tail = node.prev
        }
        
        node.prev?.next = node.next
        node.next?.prev = node.prev
    }
    
    private func evictLRU() {
        guard let lruNode = tail else { return }
        
        removeNode(lruNode)
        cache.removeValue(forKey: lruNode.key)
        
        #if DEBUG
        print("🗑️ [LRUCache] Evicted: \(lruNode.key)")
        #endif
    }
}

