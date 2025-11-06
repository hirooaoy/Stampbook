# Weekly Maintenance Checklist

Run this once a week (takes 30 seconds):

## 🔍 Check System Health

```bash
cd /Users/haoyama/Desktop/Developer/Stampbook
node reconcile_like_comment_counts.js
```

### Expected Output:

**✅ Healthy System:**
```
System Health: 100.0% accurate
🎉 Excellent! System is very healthy.
💚 RECOMMENDATION: System is healthy!
```
→ You're done! Nothing to do. ✅

**⚠️ Drift Detected:**
```
Posts with drift: 3
💛 RECOMMENDATION: Minor drift detected.
```
→ Run the fix (see below) ⬇️

## 🔧 Fix Drift (If Needed)

```bash
DRY_RUN=false node reconcile_like_comment_counts.js
```

Should see:
```
✅ All drifts have been fixed!
```

Done! ✅

---

## 📅 Recommended Schedule

- **Weekly:** Run health check
- **Monthly:** Review system health trend
- **At 100 users:** Consider running twice weekly
- **At 1000 users:** Consider Phase 3 (automation)

---

## 🚨 When to Investigate

If you see:
- ❌ System health < 95%
- ❌ Drift appearing every week
- ❌ Large drift values (>10 difference)

→ Might indicate underlying issue (network problems, bugs)

Otherwise:
- ✅ Occasional drift is NORMAL
- ✅ <5% drift is expected
- ✅ Reconciliation fixes it automatically

---

That's it! 30 seconds a week. ⏱️

