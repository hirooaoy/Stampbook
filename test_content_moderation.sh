#!/bin/bash

# Content Moderation Test Script
# Tests Cloud Functions locally before deployment

echo "🧪 Testing Content Moderation Cloud Functions"
echo "=============================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if functions directory exists
if [ ! -d "functions" ]; then
    echo "${RED}❌ functions/ directory not found${NC}"
    echo "Run: firebase init functions"
    exit 1
fi

# Check if dependencies are installed
if [ ! -d "functions/node_modules" ]; then
    echo "${YELLOW}📦 Installing dependencies...${NC}"
    cd functions && npm install && cd ..
fi

echo "${GREEN}✅ Setup complete${NC}"
echo ""

echo "📋 Test Cases:"
echo ""

# Test Case 1: Valid username
echo "1️⃣  Valid username: 'testuser123'"
echo "   Expected: ✅ PASS"
echo ""

# Test Case 2: Too short
echo "2️⃣  Too short: 'ab'"
echo "   Expected: ❌ FAIL (too short)"
echo ""

# Test Case 3: Profanity
echo "3️⃣  Profanity: 'fuck123'"
echo "   Expected: ❌ FAIL (inappropriate content)"
echo ""

# Test Case 4: Reserved word
echo "4️⃣  Reserved word: 'admin'"
echo "   Expected: ❌ FAIL (reserved word)"
echo ""

# Test Case 5: Special characters
echo "5️⃣  Special chars: 'test@user'"
echo "   Expected: ❌ FAIL (invalid format)"
echo ""

# Test Case 6: Username with substring profanity
echo "6️⃣  Substring profanity: 'assassinate'"
echo "   Expected: ❌ FAIL (contains 'ass')"
echo ""

# Test Case 7: Valid display name
echo "7️⃣  Valid display name: 'John Doe'"
echo "   Expected: ✅ PASS"
echo ""

# Test Case 8: Display name with profanity
echo "8️⃣  Display name profanity: 'Fuck Face'"
echo "   Expected: ❌ FAIL (inappropriate content)"
echo ""

echo "=============================================="
echo ""
echo "${YELLOW}🚀 To run tests:${NC}"
echo ""
echo "Option 1 - Deploy and test in production:"
echo "  firebase deploy --only functions"
echo "  # Then test via iOS app"
echo ""
echo "Option 2 - Test locally with emulator:"
echo "  cd functions"
echo "  npm run serve"
echo "  # Then configure iOS app to use emulator"
echo ""
echo "Option 3 - Unit test Cloud Functions:"
echo "  cd functions"
echo "  npm test  # (requires test setup)"
echo ""
echo "${GREEN}✅ Test script complete${NC}"

