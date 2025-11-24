import Foundation

let appGroupIdentifier = "group.com.hiroo.Stampbook"
if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
    if let data = sharedDefaults.data(forKey: "widgetStamps") {
        print("✅ Widget data exists: \(data.count) bytes")
        // Try to decode it
        if let stamps = try? JSONDecoder().decode([String].self, from: data) {
            print("📊 Found \(stamps.count) stamps")
        }
    } else {
        print("❌ No widget data found in App Group")
    }
} else {
    print("❌ Could not access App Group: \(appGroupIdentifier)")
}
