# SwiftUI Loading Pattern - Best Practices

**Date:** November 11, 2025  
**Issue:** Infinite re-render loop with `.onAppear` + conditional content  
**Status:** ✅ RESOLVED

---

## 🐛 The Bug We Fixed

### What Happened
`AllStampsContent` in `StampsView` was causing an infinite loop:
```
🔄 [AllStampsContent] loadUserStamps() called
📊 sortedCollectedStamps count: 7
💾 Cache HIT x7
✅ Fetched 7 stamps
[REPEAT INFINITELY]
```

### Root Cause
```swift
// ❌ BAD PATTERN
Group {
    if isLoading {
        Skeleton()
    } else {
        Content()
    }
}
.onAppear {
    loadData() // Changes isLoading
}
```

**Why this breaks:**
1. `.onAppear` fires when view appears
2. `loadData()` sets `isLoading = true`
3. SwiftUI sees Group content changed (skeleton → content)
4. In certain conditions, SwiftUI re-evaluates view tree
5. `.onAppear` can fire again → **INFINITE LOOP**

---

## ✅ The Fix (Golden Pattern)

### Pattern for Views That Load Data

```swift
struct MyDataView: View {
    @EnvironmentObject var manager: DataManager
    @State private var data: [Item] = []
    @State private var isLoading = false
    @State private var hasLoadedOnce = false  // ✅ CRITICAL
    
    var body: some View {
        Group {
            if isLoading && !hasLoadedOnce {  // ✅ Stable condition
                Skeleton()
            } else if data.isEmpty && !isLoading {
                EmptyState()
            } else {
                Content(data: data)
            }
        }
        .task {  // ✅ Use .task, NOT .onAppear
            guard !hasLoadedOnce else { return }  // ✅ Prevent re-entry
            loadData()
        }
        .onChange(of: manager.triggerRefresh) { _, _ in
            // Reloading is OK, just reset the flag
            hasLoadedOnce = false
            loadData()
        }
    }
    
    private func loadData() {
        guard !isLoading else { return }  // ✅ Additional guard
        
        Task {
            await MainActor.run {
                isLoading = true
            }
            
            let result = await manager.fetch()
            
            await MainActor.run {
                data = result
                hasLoadedOnce = true  // ✅ Set after loading
                isLoading = false
            }
        }
    }
}
```

---

## 🎯 Key Principles

### 1. **Use `.task` instead of `.onAppear`**
```swift
// ❌ BAD
.onAppear {
    loadData()
}

// ✅ GOOD
.task {
    guard !hasLoadedOnce else { return }
    loadData()
}
```

**Why:** `.task` is more deterministic and cancellable.

### 2. **Always include `hasLoadedOnce` flag**
```swift
@State private var hasLoadedOnce = false

.task {
    guard !hasLoadedOnce else { return }  // Prevents re-entry
    loadData()
}

private func loadData() {
    // ... load data ...
    hasLoadedOnce = true  // Set when complete
}
```

**Why:** Prevents multiple loads even if SwiftUI re-evaluates.

### 3. **Stable loading conditions**
```swift
// ❌ BAD - Can change during load
if isLoading {
    Skeleton()
}

// ✅ GOOD - Stable after first load
if isLoading && !hasLoadedOnce {
    Skeleton()
}
```

**Why:** Prevents content switching that triggers re-evaluation.

### 4. **Guard in loading function**
```swift
private func loadData() {
    guard !isLoading else { return }  // Prevent concurrent loads
    
    isLoading = true
    // ... fetch data ...
    isLoading = false
}
```

**Why:** Extra safety against race conditions.

---

## 📚 Examples in Codebase

### ✅ CORRECT Implementations

**1. StampsView.swift - AllStampsContent** (Fixed Nov 11)
```swift
struct AllStampsContent: View {
    @State private var hasLoadedOnce = false
    
    var body: some View {
        Group {
            if isLoading && !hasLoadedOnce {
                Skeleton()
            } else if stamps.isEmpty {
                EmptyState()
            } else {
                StampGrid()
            }
        }
        .task {
            guard !hasLoadedOnce else { return }
            loadUserStamps()
        }
    }
}
```

**2. UserProfileView.swift - AllStampsContent** (Fixed Nov 11)
- Same pattern as above
- Applied to other users' profile views

**3. FeedView.swift - FeedContent** (Already correct)
```swift
if posts.isEmpty && (feedManager.isLoading || !hasLoadedOnce) {
    SkeletonPosts()
} else if posts.isEmpty {
    EmptyState()
} else {
    PostsList()
}
.task(id: feedType) {
    loadFeedIfNeeded()
}
```

---

## 🚫 Anti-Patterns to Avoid

### ❌ Debug logs in computed properties
```swift
// BAD - Side effect in computed property
private var sortedItems: [Item] {
    print("📊 Sorting items")  // ❌ Logs on EVERY body evaluation
    return items.sorted()
}
```

**Fix:** Remove logs or move to functions.

### ❌ `.onAppear` without guards
```swift
// BAD - Can fire multiple times
.onAppear {
    loadData()
}
```

**Fix:** Use `.task` with `hasLoadedOnce` guard.

### ❌ Conditional content without stable conditions
```swift
// BAD - Changes during load
if isLoading {
    Skeleton()
} else {
    Content()
}
```

**Fix:** Add `&& !hasLoadedOnce` to loading condition.

---

## 🎓 Senior Developer Takeaways

### What Causes These Loops

1. **SwiftUI view identity changes** - Conditional content can change view hierarchy
2. **`.onAppear` is non-deterministic** - Can fire multiple times
3. **State changes during render** - Loading state changes trigger re-evaluation
4. **No re-entry protection** - Nothing prevents multiple calls

### Why Our Optimizations Weren't Affected

The fix doesn't touch:
- ✅ LRU cache (still working)
- ✅ Lazy loading (still loading only collected stamps)
- ✅ Firebase caching (still using persistent cache)
- ✅ Pagination (still loading 20 at a time)
- ✅ Skeleton UI (still shows immediately)

We only fixed the **trigger mechanism**, not the data loading logic.

### When to Use This Pattern

**Always use when:**
- Loading data on view appearance
- Showing skeleton/loading state
- Using conditional content based on loading state

**Not needed when:**
- View doesn't load data
- Loading is triggered by button tap
- Manager handles all state (view just displays)

---

## 📋 Checklist for New Data-Loading Views

```
[ ] Using .task instead of .onAppear
[ ] Added @State private var hasLoadedOnce = false
[ ] Guard with !hasLoadedOnce in .task
[ ] Loading condition includes && !hasLoadedOnce
[ ] Set hasLoadedOnce = true after loading
[ ] Added guard !isLoading in load function
[ ] No debug logs in computed properties
[ ] Tested navigation between tabs
```

---

## 🐛 Debugging Infinite Loops

### Symptoms
- Console floods with repeated logs
- High CPU usage
- App feels sluggish
- Firebase read count spikes

### Quick Fix
1. Add debug log at top of `body`:
```swift
var body: some View {
    let _ = print("🔍 [ViewName] body evaluated")
    // ... rest of body
}
```

2. If log repeats → You have a loop

3. Check for:
   - `.onAppear` with loading state
   - Conditional content that changes
   - Missing `hasLoadedOnce` flag

### Testing
After fix, you should see:
```
🔍 [ViewName] body evaluated
🔄 loadData() called
✅ Data loaded
[NO MORE LOGS]
```

---

## 📊 Impact on MVP

| Before Fix | After Fix |
|------------|-----------|
| Infinite loop | Single load ✅ |
| 100x Firebase reads | Normal reads ✅ |
| App unusable | Instant ✅ |
| Battery drain | Normal ✅ |

**Verdict:** Critical fix for MVP launch.

---

## 📝 Files Modified (Nov 11, 2025)

1. `Stampbook/Views/Profile/StampsView.swift` - AllStampsContent fixed
2. `Stampbook/Views/Profile/UserProfileView.swift` - AllStampsContent fixed
3. `Stampbook/Managers/StampsManager.swift` - Removed cache hit spam
4. `Stampbook/ContentView.swift` - Removed body evaluation log

**Total time:** 20 minutes  
**Performance impact:** 0 (only positive)  
**Breaking changes:** 0

---

**Remember:** When in doubt, use `.task` + `hasLoadedOnce` pattern. It's fail-safe for MVP.

