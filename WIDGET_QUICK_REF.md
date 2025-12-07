# Widget Quick Reference

## Check Widget Status
```bash
cd /Users/haoyama/Desktop/Developer/Stampbook
swift trigger_widget_sync.swift
```

## What You Should See

### Before Running App
```
⚠️ No widgetStamps key found - app needs to sync
⚠️ No Images directory or can't read it
```

### After Running App (Success)
```
✅ Decoded X stamps:
  1. Golden Gate Bridge (us-ca-san-francisco-golden-gate-bridge)
     Image: us-ca-san-francisco-golden-gate-bridge.png
  2. ...
📸 Images in shared container: X files
```

## Debug in Console.app (On Device)

1. Connect iPhone to Mac
2. Open Console.app
3. Filter logs by: `Widget` or `StampsManager`
4. Run Stampbook app
5. Look for success messages:
   - `✅ [Widget] Syncing X stamps to widget`
   - `📸 [Widget] ✅ Copied image for stamp: xxx`
   - `✅ [Widget] Widget timelines reloaded`

## Key Improvements Made

1. **Automatic Image Download**: Widget now downloads images from Firebase if not cached
2. **Better Error Handling**: Graceful fallbacks, no crashes if images missing
3. **Enhanced Logging**: Detailed messages in Console.app for debugging
4. **Visual Polish**: Better placeholder layout when images loading

## Testing Checklist

- [ ] Run app on physical iPhone (widgets don't work in Simulator)
- [ ] Check widget status with diagnostic script
- [ ] Add widget to home screen
- [ ] Verify widget shows stamp image (may take 5-30 seconds)
- [ ] Collect a new stamp, verify widget updates
- [ ] Check Console.app for any error messages

## Common Issues

**Widget shows placeholder instead of image:**
- Wait 5-30 seconds for sync to complete
- Check Console.app logs for download errors
- Run diagnostic script to verify images in shared container

**Widget says "Collect a stamp to display":**
- User has no collected stamps yet (correct behavior)
- Or sync hasn't run yet (open app to trigger)

**Widget not updating after collecting stamp:**
- iOS controls widget refresh timing (not immediate)
- Can take up to 30 seconds
- Force refresh: Switch to widget extension scheme and run in Xcode

## Files Modified

- `Stampbook/Managers/StampsManager.swift` - Enhanced image copy logic
- `StampbookWidget/StampWidgetView.swift` - Better layout and clipping
- `Stampbook/Models/WidgetStamp.swift` - Enhanced debugging logs
- `trigger_widget_sync.swift` - New diagnostic tool

---

**Status:** ✅ Ready to test on device
**Next:** Build on iPhone and verify widget appears

