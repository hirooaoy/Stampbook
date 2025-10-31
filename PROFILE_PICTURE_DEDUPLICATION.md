# Profile Picture Download Deduplication

## Problem

When the app loaded, the same profile picture was being downloaded **10 times simultaneously**:

```
⬇️ Downloading profile picture from: https://...mpd4k2n13adMFMY52nksmaQTbMQ2/profile_photo/...
⬇️ Downloading profile picture from: https://...mpd4k2n13adMFMY52nksmaQTbMQ2/profile_photo/...
⬇️ Downloading profile picture from: https://...mpd4k2n13adMFMY52nksmaQTbMQ2/profile_photo/...
(... 7 more times)
```

This was causing:
- **10x redundant network requests** for the same image
- **10x cache writes** for the same data
- Wasted bandwidth and Firebase egress costs
- Slower loading due to network congestion

### Root Cause

Multiple `ProfileImageView` instances were simultaneously requesting the same profile picture URL:
1. User has 10 stamps on the map
2. Each stamp marker shows profile picture
3. All 10 markers load simultaneously
4. No deduplication = 10 parallel downloads of **identical** image

## Solution

Added **in-flight request tracking** to `ImageManager`:

### 1. Track Active Downloads

```swift
private var inFlightProfilePictures: [String: Task<UIImage, Error>] = [:]
private let profilePictureQueue = DispatchQueue(label: "com.stampbook.profilePictureQueue")
```

### 2. Deduplicate Concurrent Requests

Modified `downloadAndCacheProfilePicture(url:userId:)`:

```swift
// Check if there's already a download in progress
if let existingTask = inFlightProfilePictures[url] {
    print("⏳ Waiting for in-flight profile picture download")
    return try await existingTask.value  // Wait for existing download
}

// Create new download task and register it
let downloadTask = Task<UIImage, Error> { ... }
inFlightProfilePictures[url] = downloadTask

// Clean up after completion
defer {
    inFlightProfilePictures.removeValue(forKey: url)
}
```

## How It Works

### Before Fix
```
Request 1 → Download → Cache
Request 2 → Download → Cache
Request 3 → Download → Cache
... (10 total downloads)
```

### After Fix
```
Request 1 → Download → Cache → Share result with 2-10
Request 2 → Wait for Request 1
Request 3 → Wait for Request 1
... (1 total download)
```

## Expected Results

After this fix, you should see:
```
⬇️ Downloading profile picture from: https://...  (1 time only)
⏳ Waiting for in-flight profile picture download (9 times)
✅ Profile picture cached locally (1 time only)
```

**Bandwidth savings**: 90% reduction (1 download instead of 10)
**Firebase costs**: 90% reduction in egress charges
**Loading time**: Faster due to less network congestion

## Testing

Run the app and check the logs:
1. Should see only 1 "Downloading profile picture" message per unique URL
2. Should see 9 "Waiting for in-flight" messages
3. Should see only 1 "cached locally" message per unique image

## Notes

- This fix only applies to profile pictures (the most common case)
- Stamp photos already had some deduplication via `FeedManager` prefetching
- Memory and disk caches still checked first (fastest path)
- Thread-safe using `DispatchQueue.sync` for dictionary access

