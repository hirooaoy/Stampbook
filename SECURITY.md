# Security Guidelines

## 🔒 Sensitive Files - DO NOT COMMIT

The following files contain sensitive credentials and must NEVER be committed to version control:

### ⚠️ CRITICAL - Backend Service Credentials

- **`serviceAccountKey.json`** - Firebase Admin SDK service account key
  - Contains private keys that grant full backend access
  - If exposed: attackers can read/write all database data, delete user accounts, and disable your backend
  - Already in `.gitignore` ✅
  - Use `serviceAccountKey.json.template` as a reference for structure

### 📱 Client Configuration

- **`GoogleService-Info.plist`** - Firebase iOS client configuration
  - Contains API keys and project identifiers
  - Already in `.gitignore` ✅
  - Use `GoogleService-Info.plist.template` as a reference for structure

## 🛡️ What To Do If Credentials Are Exposed

If you accidentally commit sensitive credentials:

1. **Immediately revoke the credentials** in Firebase Console:
   - Go to Project Settings → Service Accounts
   - Delete the compromised service account
   - Generate a new service account key

2. **Remove from git history** (this is complex, get help):
   ```bash
   # DO NOT run this without understanding it first
   git filter-branch --force --index-filter \
     "git rm --cached --ignore-unmatch serviceAccountKey.json" \
     --prune-empty --tag-name-filter cat -- --all
   ```

3. **Force push to remote** (WARNING: coordinates with team first):
   ```bash
   git push origin --force --all
   ```

4. **Notify team members** to re-clone the repository

## ✅ Current Status

- [x] `serviceAccountKey.json` is gitignored
- [x] `GoogleService-Info.plist` is gitignored
- [x] Template files created for reference
- [x] No sensitive credentials in git history

## 📝 Setup for New Developers

1. Clone the repository
2. Copy template files:
   ```bash
   cp serviceAccountKey.json.template serviceAccountKey.json
   cp GoogleService-Info.plist.template Stampbook/GoogleService-Info.plist
   ```
3. Fill in actual credentials from Firebase Console
4. **Never commit these files** - they're already in `.gitignore`

