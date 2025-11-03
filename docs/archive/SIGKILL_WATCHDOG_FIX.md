# SIGKILL Watchdog Timeout Fix

**Date:** November 3, 2025  
**Issue:** App crashing with `SIGKILL` signal in `dyld`  
**Root Cause:** Watchdog timeout during app launch

---

## 🔴 What is SIGKILL?

`SIGKILL` (signal 9) is a **forced termination** by iOS. Unlike crashes you can catch, this is the OS saying "your app is unresponsive, I'm killing it."

**Common causes:**
1. **Watchdog timeout** ⏱️ - App took >20 seconds to launch or respond
2. **Memory pressure** 💾 - App used too much RAM
3. **Jetsam** - iOS memory manager killed the app
4. **Code signing issues** - Entitlements/provisioning problems

In your case: **Watchdog timeout during app launch**

---

## 🐛 Root Cause: Synchronous Auth Check

### The Problem

**File:** `AuthManager.swift`

```swift
// BEFORE (❌ BLOCKS MAIN THREAD)
override init() {
    super.init()
    checkAuthState()  // Synchronous Firebase call on main thread!
}

private func checkAuthState() {
    if let currentUser = Auth.auth().currentUser {
        // ...
        Task {
            await loadUserProfile(userId: currentUser.uid)  // Firebase network call
        }
    }
}
```

**Why this causes SIGKILL:**

1. `AuthManager` is a `@StateObject` in `StampbookApp`
2. `@StateObject` properties initialize **synchronously on main thread** during app launch
3. `checkAuthState()` runs immediately, accessing `FirebaseService.shared`
4. If Firebase is slow (network issues, cold start), this blocks the main thread
5. iOS watchdog detects main thread blocked for >20 seconds → **SIGKILL**

### The Chain Reaction

```
App Launch (main thread)
  ↓
StampbookApp init()
  ↓
@StateObject var authManager = AuthManager()  [BLOCKS HERE]
  ↓
AuthManager.init()
  ↓
checkAuthState()
  ↓
Auth.auth().currentUser  [Firebase SDK call]
  ↓
FirebaseService.shared  [Triggers singleton init]
  ↓
... 20+ seconds later ...
  ↓
iOS Watchdog: "App unresponsive" → SIGKILL
```

---

## ✅ Solution: Defer Heavy Work

### Changes Made

#### 1. **AuthManager.swift** - Async Auth Check

```swift
// AFTER (✅ NON-BLOCKING)
override init() {
    super.init()
    print("⏱️ [AuthManager] init() started")
    
    // Defer auth check to avoid blocking app launch
    Task.detached(priority: .high) { [weak self] in
        await self?.checkAuthState()
    }
    
    print("⏱️ [AuthManager] init() completed (auth check deferred)")
}

/// Check if user is already signed in with Firebase
private func checkAuthState() async {
    print("⏱️ [AuthManager] checkAuthState() started")
    
    guard let currentUser = Auth.auth().currentUser else {
        print("ℹ️ [AuthManager] No user signed in")
        return
    }
    
    // Update auth state on main thread
    await MainActor.run {
        self.userId = currentUser.uid
        self.userDisplayName = currentUser.displayName ?? "User"
        self.isSignedIn = true
        print("✅ [AuthManager] User already signed in: \(currentUser.uid)")
    }
    
    // Load user profile from Firestore (in background)
    await loadUserProfile(userId: currentUser.uid)
    
    print("⏱️ [AuthManager] checkAuthState() completed")
}
```

**Key improvements:**
- `init()` returns instantly (no blocking)
- `checkAuthState()` runs in detached task (off main thread)
- Auth state updates happen on `MainActor` when ready
- User sees app immediately, auth state syncs in background

#### 2. **StampbookApp.swift** - Startup Timing Logs

```swift
// MARK: - App Delegate
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        print("⏱️ [AppDelegate] didFinishLaunching started")
        FirebaseApp.configure()
        print("⏱️ [AppDelegate] Firebase configured")
        return true
    }
}

@main
struct StampbookApp: App {
    init() {
        print("⏱️ [StampbookApp] App init() started")
    }
    
    @StateObject private var authManager = AuthManager()
    // ... other state objects ...
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                // ... environment objects ...
                .onAppear {
                    print("⏱️ [StampbookApp] ContentView appeared - App launch complete")
                }
        }
    }
}
```

---

## 📊 Expected Console Output (Good Launch)

If the fix works, you should see:

```
⏱️ [AppDelegate] didFinishLaunching started
⏱️ [AppDelegate] Firebase configured
⏱️ [StampbookApp] App init() started
⏱️ [AuthManager] init() started
⏱️ [AuthManager] init() completed (auth check deferred)
⏱️ [StampbookApp] ContentView appeared - App launch complete
⏱️ [AuthManager] checkAuthState() started
✅ [AuthManager] User already signed in: abc123
🔄 [AuthManager] Loading user profile for userId: abc123
⏱️ [AuthManager] checkAuthState() completed
```

**Timeline:**
- **T+0ms**: AppDelegate starts
- **T+100ms**: Firebase configured
- **T+200ms**: AuthManager init (returns instantly)
- **T+500ms**: ContentView appears → **APP LAUNCH COMPLETE** ✅
- **T+1000ms**: Auth check completes in background

**Critical:** ContentView appears **before** auth check completes. This prevents watchdog timeout.

---

## 🚨 If Still Crashing

### Step 1: Check Console Logs

Look for timing issues:

```bash
# In Xcode Console
⏱️ [AppDelegate] didFinishLaunching started
... (gap longer than 5 seconds?) ...
⏱️ [AppDelegate] Firebase configured  # <-- If this takes >10s, Firebase config is blocking
```

### Step 2: Check Other Managers

Other `@StateObject` managers might also be blocking:

- `NetworkMonitor` - Check if it does network requests on init
- `FollowManager` - Check if it loads data on init
- `BlockManager` - Check if it loads blocked users on init
- `ProfileManager` - Check if it loads profiles on init

**Rule:** All `@StateObject` init() must return **instantly** (<100ms)

### Step 3: Check FirebaseService Init

```swift
// File: FirebaseService.swift
private init() {
    // ...
    Task.detached(priority: .background) {
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await self.runConnectivityDiagnostics()  # <-- This should NOT block
    }
}
```

If `runConnectivityDiagnostics()` is somehow blocking, increase the delay or remove it.

### Step 4: Memory Issues

If logs show fast startup but still SIGKILL, check memory:

```swift
// Add to AppDelegate
print("📊 [Memory] App using \(ProcessInfo.processInfo.physicalMemory / 1024 / 1024) MB")
```

If memory usage is >200MB on iPhone 8 or older, optimize image caching.

### Step 5: Test on Physical Device

Simulator has different performance characteristics. Test on:
- iPhone 8 or older (slower, triggers watchdog more easily)
- Poor network conditions
- Low battery mode

---

## 🎯 Best Practices: iOS App Launch

### ✅ Do
1. **Defer all network calls** - Use `Task.detached` or `.onAppear`
2. **Keep inits fast** - `@StateObject` init() should take <10ms
3. **Use offline persistence** - Show cached data immediately
4. **Progressive loading** - Show UI first, load data after
5. **Add timing logs** - Track where time is spent

### ❌ Don't
1. **Block main thread** - No synchronous network calls
2. **Load all data on launch** - Lazy load what you need
3. **Wait for Firebase** - Use offline mode, sync in background
4. **Assume fast network** - Design for 3G/slow networks
5. **Trust simulator** - Always test on real device

---

## 📝 Testing Checklist

- [ ] Run on iPhone 15 simulator (fast baseline)
- [ ] Run on iPhone 8 simulator (slower, catches issues)
- [ ] Run on physical device (oldest device you support)
- [ ] Test with airplane mode on (offline start)
- [ ] Test with Network Link Conditioner (3G speed)
- [ ] Check Console for timing logs (all <5s)
- [ ] Monitor memory usage (<150MB on launch)
- [ ] Test cold start (kill app, relaunch)
- [ ] Test warm start (background, foreground)

---

## 🔍 Debug Symbols

If crash happens in `dyld`:

```
Thread 1: signal SIGKILL
dyld`lldb_image_notifier:
->  0x1005eb78c <+0>: ret
```

This means:
- iOS killed the app **before** your code could run
- Happened during dynamic linker phase (loading frameworks)
- Usually means app took too long to become responsive
- Fix by optimizing startup (see above)

---

## 📚 References

- [Apple: Understanding Watchdog Terminations](https://developer.apple.com/documentation/xcode/understanding-watchdog-terminations)
- [CRITICAL_FIRESTORE_FIX.md](./CRITICAL_FIRESTORE_FIX.md) - Previous blocking issues
- [LAZY_LOADING_OPTIMIZATION.md](./LAZY_LOADING_OPTIMIZATION.md) - Lazy loading pattern
- [INSTAGRAM_PATTERN_IMPLEMENTATION.md](./INSTAGRAM_PATTERN_IMPLEMENTATION.md) - Perceived performance

---

## ✅ Status

**Fixed:** AuthManager no longer blocks app launch  
**Next:** Run in Xcode and verify timing logs show fast startup (<1s to ContentView)

If issue persists, check other managers and Firebase initialization.

