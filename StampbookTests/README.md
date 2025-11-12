# Stampbook Tests

Essential tests for MVP - covers the most critical functionality to prevent embarrassing bugs as you scale from 2 to 10+ users.

## Test Files

1. **StampCollectionTests.swift** - Distance calculations and collection radius logic (your core mechanic)
2. **InviteCodeTests.swift** - Invite code validation (controls growth)
3. **StampVisibilityTests.swift** - Moderation and visibility system
4. **CountryParsingTests.swift** - Address parsing for profile stats
5. **LikeManagerTests.swift** - Like/unlike logic (prevents count bugs)

## Setup in Xcode

### 1. Add test files to Xcode project

1. Open `Stampbook.xcodeproj` in Xcode
2. In the Project Navigator (left sidebar), find the `StampbookTests` folder/group
3. Right-click `StampbookTests` → Add Files to "Stampbook"...
4. Select all 5 `.swift` files in the `StampbookTests` directory
5. Make sure "Add to targets: StampbookTests" is checked
6. Click "Add"

### 2. Running tests

**Run all tests:**
- Press `Cmd+U` (or Product → Test)
- All 5 test files will run (~2 seconds)
- You'll see green checkmarks for passing tests

**Run a single test file:**
- Click the diamond icon next to the class name
- Or use Test Navigator (`Cmd+6`) and click the test

**Run a single test:**
- Click the diamond icon next to the function name

### 3. When to run tests

**Before every TestFlight upload:**
```bash
# In Xcode, press Cmd+U
# Wait for green checkmarks
# Then build for TestFlight
```

**After making changes to:**
- Distance/location calculations
- Like/unlike logic
- Invite code validation
- Stamp visibility/moderation
- Address parsing

**When adding user #11, #12, etc.:**
- Run tests to catch any bugs before they affect real users

## Test Coverage

These 5 files cover:
- ✅ 150m collection radius accuracy
- ✅ All 4 radius types (regular, regularplus, large, xlarge)
- ✅ Invite code formatting (uppercase, trim)
- ✅ Code validation (empty, expired, fully used)
- ✅ Stamp visibility (active, hidden, removed)
- ✅ Date-based availability (future events)
- ✅ Country extraction from addresses (US, Japan, UK, France)
- ✅ Like count logic (never negative, optimistic updates)
- ✅ Multiple likes across different posts

Total: **~50 tests** covering your most critical bugs.

## What's NOT tested (intentionally)

To save time, we don't test:
- Firebase SDK methods (Google already tested those)
- SwiftUI view rendering (Apple tested that)
- Network connectivity
- Image upload/download
- Simple getters/setters

## Next Steps

Once you have these working, you can add:
- Integration tests (test with actual Firebase calls)
- UI tests (test critical user flows like sign-in)
- Performance tests (test with 1000+ stamps)

But for now, these unit tests give you 90% of the value with 10% of the effort.

## Troubleshooting

**Tests not showing up?**
- Make sure files are added to the `StampbookTests` target (not `Stampbook`)
- In Xcode, select a test file → File Inspector (right sidebar) → Target Membership → Check `StampbookTests`

**Import errors?**
- Make sure `@testable import Stampbook` is at the top of each file
- This gives tests access to your app's internal code

**Tests failing?**
- Read the error message carefully
- The test name usually tells you what broke
- Fix the underlying code, not the test

## Running from Terminal (CI/CD)

```bash
# Run all tests from command line
xcodebuild test -scheme Stampbook -destination 'platform=iOS Simulator,name=iPhone 15'
```

You can add this to GitHub Actions to run tests automatically on every push.

