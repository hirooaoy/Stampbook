#!/usr/bin/env swift
import Foundation

// Trigger widget sync by posting notification
// This simulates what happens when stamps are loaded

print("🔔 Triggering widget sync...")
print("Note: This script checks the current state. To trigger actual sync, run the app.")

let appGroupIdentifier = "group.com.hiroo.Stampbook"

// Check current state
if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
    print("✅ Connected to shared UserDefaults")
    
    // Check for widget stamps data
    if let data = sharedDefaults.data(forKey: "widgetStamps") {
        print("📊 Widget stamps data exists (\(data.count) bytes)")
        
        struct WidgetStamp: Codable {
            let id: String
            let name: String
            let collectedDate: Date
            let imageFileName: String
        }
        
        if let stamps = try? JSONDecoder().decode([WidgetStamp].self, from: data) {
            print("✅ Decoded \(stamps.count) stamps:")
            for (index, stamp) in stamps.enumerated() {
                print("  \(index + 1). \(stamp.name) (\(stamp.id))")
                print("     Image: \(stamp.imageFileName)")
            }
        } else {
            print("⚠️ Failed to decode widget stamps")
        }
    } else {
        print("⚠️ No widgetStamps key found - app needs to sync")
    }
    
    // Check shared container
    if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
        print("\n📂 Shared container: \(containerURL.path)")
        
        let imagesDir = containerURL.appendingPathComponent("Images")
        if let files = try? FileManager.default.contentsOfDirectory(atPath: imagesDir.path) {
            print("📸 Images in shared container: \(files.count) files")
            if files.isEmpty {
                print("   (No images yet - app needs to copy them)")
            } else {
                print("   First 10:")
                for file in files.prefix(10) {
                    let fileURL = imagesDir.appendingPathComponent(file)
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                       let fileSize = attrs[.size] as? Int64 {
                        print("   - \(file) (\(fileSize / 1024) KB)")
                    } else {
                        print("   - \(file)")
                    }
                }
                if files.count > 10 {
                    print("   ... and \(files.count - 10) more")
                }
            }
        } else {
            print("⚠️ No Images directory or can't read it")
        }
    } else {
        print("⚠️ Can't access shared container")
    }
    
    print("\n💡 To trigger sync:")
    print("   1. Open the Stampbook app")
    print("   2. Sync happens automatically on app launch")
    print("   3. Or collect a new stamp to trigger immediate sync")
    
} else {
    print("❌ Failed to connect to shared UserDefaults")
}

