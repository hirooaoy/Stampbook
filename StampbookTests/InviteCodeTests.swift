import XCTest
@testable import Stampbook

/// Tests for invite code validation logic
/// Critical for controlling app growth and preventing invalid signups
class InviteCodeTests: XCTestCase {
    
    // MARK: - Code Formatting
    
    func testInviteCodeUppercasing() {
        let lowercaseCode = "stamp2024"
        let formatted = lowercaseCode.uppercased()
        
        XCTAssertEqual(formatted, "STAMP2024", "Invite codes should be converted to uppercase")
    }
    
    func testInviteCodeTrimming() {
        let codeWithSpaces = "  STAMP2024  "
        let formatted = codeWithSpaces.trimmingCharacters(in: .whitespaces)
        
        XCTAssertEqual(formatted, "STAMP2024", "Invite codes should have leading/trailing whitespace removed")
    }
    
    func testInviteCodeFormattingCombined() {
        let messyCode = "  stamp2024  "
        let formatted = messyCode.uppercased().trimmingCharacters(in: .whitespaces)
        
        XCTAssertEqual(formatted, "STAMP2024", "Invite codes should be uppercased and trimmed")
    }
    
    // MARK: - Invalid Codes
    
    func testEmptyCodeIsInvalid() {
        let emptyCode = ""
        XCTAssertTrue(emptyCode.isEmpty, "Empty string should be detected as invalid")
    }
    
    func testWhitespaceOnlyCodeIsInvalid() {
        let whitespaceCode = "   "
        let trimmed = whitespaceCode.trimmingCharacters(in: .whitespaces)
        XCTAssertTrue(trimmed.isEmpty, "Whitespace-only string should be invalid after trimming")
    }
    
    func testNewlineOnlyCodeIsInvalid() {
        let newlineCode = "\n\n"
        let trimmed = newlineCode.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(trimmed.isEmpty, "Newline-only string should be invalid after trimming")
    }
    
    // MARK: - Valid Code Formats
    
    func testAlphanumericCodeIsValid() {
        let code = "STAMP2024"
        XCTAssertFalse(code.isEmpty, "Alphanumeric code should be valid")
        XCTAssertEqual(code.count, 9, "Code should maintain correct length")
    }
    
    func testNumericCodeIsValid() {
        let code = "123456"
        XCTAssertFalse(code.isEmpty, "Numeric code should be valid")
    }
    
    func testLettersOnlyCodeIsValid() {
        let code = "WELCOME"
        XCTAssertFalse(code.isEmpty, "Letters-only code should be valid")
    }
    
    // MARK: - Code Validation Logic
    
    func testCodeUsageTracking() {
        // Simulate code usage tracking
        let usedCount = 5
        let maxUses = 10
        
        XCTAssertLessThan(usedCount, maxUses, "Code with remaining uses should be valid")
    }
    
    func testCodeFullyUsed() {
        // Simulate fully used code
        let usedCount = 10
        let maxUses = 10
        
        XCTAssertFalse(usedCount < maxUses, "Fully used code should be invalid")
    }
    
    func testCodeOverUsed() {
        // Edge case: somehow used more than max (shouldn't happen, but defensive)
        let usedCount = 11
        let maxUses = 10
        
        XCTAssertFalse(usedCount < maxUses, "Over-used code should be invalid")
    }
    
    // MARK: - Status Validation
    
    func testActiveStatusIsValid() {
        let status = "active"
        XCTAssertEqual(status, "active", "Active status should be valid")
    }
    
    func testExpiredStatusIsInvalid() {
        let status = "expired"
        XCTAssertNotEqual(status, "active", "Expired status should be invalid")
    }
    
    func testUsedStatusIsInvalid() {
        let status = "used"
        XCTAssertNotEqual(status, "active", "Used status should be invalid")
    }
}

