const admin = require('firebase-admin');

// Initialize Firebase Admin (if not already initialized)
if (!admin.apps.length) {
    const serviceAccount = require('./serviceAccountKey.json');
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
    });
}

const db = admin.firestore();

async function fixNegativeCommentCounts() {
    try {
        console.log('\n🔍 Scanning all users for negative comment counts...\n');
        
        let totalUsers = 0;
        let totalStamps = 0;
        let negativeCountsFound = 0;
        let negativeCountsFixed = 0;
        
        // Get all users
        const usersSnapshot = await db.collection('users').get();
        totalUsers = usersSnapshot.size;
        
        console.log(`📊 Found ${totalUsers} users to check\n`);
        
        for (const userDoc of usersSnapshot.docs) {
            const userId = userDoc.id;
            
            // Get all collected stamps for this user
            const stampsSnapshot = await db
                .collection('users')
                .doc(userId)
                .collection('collectedStamps')
                .get();
            
            totalStamps += stampsSnapshot.size;
            
            for (const stampDoc of stampsSnapshot.docs) {
                const data = stampDoc.data();
                const stampId = stampDoc.id;
                
                // Check for negative or undefined commentCount
                if (data.commentCount < 0) {
                    console.log(`❌ Found negative commentCount: ${data.commentCount}`);
                    console.log(`   User: ${userId}`);
                    console.log(`   Stamp: ${stampId}`);
                    console.log(`   Post ID: ${userId}-${stampId}`);
                    
                    negativeCountsFound++;
                    
                    // Fix it by setting to 0
                    try {
                        await stampDoc.ref.update({
                            commentCount: 0
                        });
                        console.log(`✅ Fixed: Set commentCount to 0\n`);
                        negativeCountsFixed++;
                    } catch (error) {
                        console.log(`⚠️ Failed to fix: ${error.message}\n`);
                    }
                }
                
                // Also check for undefined/null commentCount
                if (data.commentCount === undefined || data.commentCount === null) {
                    console.log(`⚠️ Found undefined commentCount`);
                    console.log(`   User: ${userId}`);
                    console.log(`   Stamp: ${stampId}`);
                    
                    // Initialize to 0
                    try {
                        await stampDoc.ref.update({
                            commentCount: 0
                        });
                        console.log(`✅ Initialized commentCount to 0\n`);
                    } catch (error) {
                        console.log(`⚠️ Failed to initialize: ${error.message}\n`);
                    }
                }
            }
        }
        
        console.log('\n📊 Summary:');
        console.log(`   Total users scanned: ${totalUsers}`);
        console.log(`   Total stamps scanned: ${totalStamps}`);
        console.log(`   Negative counts found: ${negativeCountsFound}`);
        console.log(`   Negative counts fixed: ${negativeCountsFixed}`);
        
        if (negativeCountsFound === 0) {
            console.log('\n✅ No negative comment counts found!');
        } else if (negativeCountsFixed === negativeCountsFound) {
            console.log('\n✅ All negative comment counts have been fixed!');
        } else {
            console.log('\n⚠️ Some negative counts could not be fixed. Check errors above.');
        }
        
        process.exit(0);
    } catch (error) {
        console.error('\n❌ Error:', error);
        process.exit(1);
    }
}

fixNegativeCommentCounts();

