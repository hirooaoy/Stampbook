const admin = require('firebase-admin');

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

async function createAdminAccount() {
  try {
    const email = 'admin@stampbook.app';
    const password = 'stampbook2024'; // Change this to whatever you want
    
    // Create admin user
    const userRecord = await admin.auth().createUser({
      email: email,
      password: password,
      emailVerified: true
    });

    console.log('✅ Admin account created successfully!');
    console.log('Email:', email);
    console.log('Password:', password);
    console.log('UID:', userRecord.uid);
    console.log('\nYou can now use these credentials to log into the admin upload page.');
    console.log('⚠️  Remember to change the password after first login!');

  } catch (error) {
    if (error.code === 'auth/email-already-exists') {
      console.log('✅ Admin account already exists!');
      console.log('Email: admin@stampbook.app');
      console.log('Use your existing password to login.');
    } else {
      console.error('❌ Error creating admin account:', error);
    }
  } finally {
    process.exit();
  }
}

createAdminAccount();

