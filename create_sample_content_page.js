#!/usr/bin/env node

/**
 * Script to create a sample content page in Firestore
 * This demonstrates the ContentPage structure for local businesses, creators, or app info
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

const db = admin.firestore();

// Partnership page for local businesses
const partnershipPage = {
  id: "partner-with-stampbook",
  title: "Create a Stamp for Your Business",
  type: "local_business",
  sections: [
    {
      type: "text",
      order: 0,
      content: "Have a café, shop, or local spot people love?\n\nYou can create your own digital stamp that explorers collect when they visit."
    },
    {
      type: "text",
      order: 1,
      content: "Every partner gets to write their own \"About\" story, and you'll work directly with me to design a stamp that captures your vibe."
    },
    {
      type: "divider",
      order: 2
    },
    {
      type: "text",
      order: 3,
      content: "We're still early and small — I'm a solo developer building this idea and growing the community one place at a time.\n\nIf you like the vision, I'd love to collaborate with you."
    },
    {
      type: "divider",
      order: 4
    },
    {
      type: "text",
      order: 5,
      content: "💰 Offer: $25 for a 6-month listing\n(Early partner spots only)"
    },
    {
      type: "divider",
      order: 6
    },
    {
      type: "link",
      order: 7,
      linkUrl: "mailto:partner@stampbook.app?subject=Partnership%20Interest&body=Hi!%20I'd%20love%20to%20create%20a%20stamp%20for%20my%20business.",
      linkLabel: "→ Let's Chat"
    },
    {
      type: "text",
      order: 8,
      content: "(We'll collaborate on your design and story)"
    }
  ],
  lastUpdated: admin.firestore.FieldValue.serverTimestamp()
};

// Creator collaboration page
const creatorPage = {
  id: "become-a-creator",
  title: "Help Build Stampbook",
  type: "creator",
  sections: [
    {
      type: "text",
      order: 0,
      content: "Know amazing places that should be stamps?\n\nI'm looking for passionate locals who want to help curate experiences in their city."
    },
    {
      type: "text",
      order: 1,
      content: "As a Creator, you'll:\n\n• Suggest new stamp locations\n• Write compelling descriptions\n• Share insider tips and recommendations\n• Get credited on the stamps you create"
    },
    {
      type: "divider",
      order: 2
    },
    {
      type: "text",
      order: 3,
      content: "This is perfect for:\n\n📍 Local guides and tour leaders\n✈️ Travel bloggers\n🎨 People who love their city\n🗺️ Community builders"
    },
    {
      type: "divider",
      order: 4
    },
    {
      type: "text",
      order: 5,
      content: "We're still small and scrappy. You'd be working directly with me to shape how people discover your city."
    },
    {
      type: "divider",
      order: 6
    },
    {
      type: "link",
      order: 7,
      linkUrl: "mailto:hello@stampbook.app?subject=Creator%20Application&body=Hi!%20I'd%20love%20to%20help%20create%20stamps.%0A%0AMy%20city:%20%0AMy%20favorite%20local%20spots:%20%0AWhy%20I'm%20interested:%20",
      linkLabel: "→ Apply to Be a Creator"
    }
  ],
  lastUpdated: admin.firestore.FieldValue.serverTimestamp()
};

// About page with origin story
const aboutStampbookPage = {
  id: "about-stampbook",
  title: "About Stampbook",
  type: "about",
  sections: [
    {
      type: "text",
      order: 0,
      content: "Stampbook is a love letter to the places that make us feel something."
    },
    {
      type: "divider",
      order: 1
    },
    {
      type: "text",
      order: 2,
      content: "The idea came to me after years of taking photos at beautiful places, then forgetting where they were taken or why they mattered."
    },
    {
      type: "text",
      order: 3,
      content: "I wanted a way to:\n\n• Remember the places I've been\n• Discover hidden gems from locals\n• Collect experiences, not just photos\n• Share the joy of exploration"
    },
    {
      type: "divider",
      order: 4
    },
    {
      type: "text",
      order: 5,
      content: "So I built Stampbook — a digital passport for real-world adventures."
    },
    {
      type: "text",
      order: 6,
      content: "Every location is carefully curated. Every stamp tells a story. And every collection is a map of your memories."
    },
    {
      type: "divider",
      order: 7
    },
    {
      type: "text",
      order: 8,
      content: "We're still tiny — just me and a small community of early explorers. But we're growing one stamp, one place, one memory at a time."
    },
    {
      type: "divider",
      order: 9
    },
    {
      type: "text",
      order: 10,
      content: "Built with ❤️ in San Francisco by Hiroo"
    },
    {
      type: "divider",
      order: 11
    },
    {
      type: "link",
      order: 12,
      linkUrl: "mailto:hello@stampbook.app",
      linkLabel: "Get in Touch"
    },
    {
      type: "link",
      order: 13,
      linkUrl: "https://instagram.com/stampbook",
      linkLabel: "Follow Our Journey"
    }
  ],
  lastUpdated: admin.firestore.FieldValue.serverTimestamp()
};

async function createSampleContentPages() {
  try {
    console.log('Creating strategic content pages...\n');
    
    // Create Partnership page
    console.log('Creating partnership page');
    await db.collection('contentPages').doc(partnershipPage.id).set(partnershipPage);
    console.log('✅ Created: contentPages/' + partnershipPage.id);
    
    // Create Creator collaboration page
    console.log('\nCreating creator collaboration page');
    await db.collection('contentPages').doc(creatorPage.id).set(creatorPage);
    console.log('✅ Created: contentPages/' + creatorPage.id);
    
    // Create About Stampbook page
    console.log('\nCreating about page');
    await db.collection('contentPages').doc(aboutStampbookPage.id).set(aboutStampbookPage);
    console.log('✅ Created: contentPages/' + aboutStampbookPage.id);
    
    console.log('\n✨ Strategic content pages created successfully!');
    console.log('\n📝 Next steps:');
    console.log('1. Add these pages to your Settings/Profile menu with:');
    console.log('   - ContentPageView(contentPageId: "partner-with-stampbook")');
    console.log('   - ContentPageView(contentPageId: "become-a-creator")');
    console.log('   - ContentPageView(contentPageId: "about-stampbook")');
    console.log('2. Deploy Firestore rules: firebase deploy --only firestore:rules');
    console.log('3. Test the pages in your app!');
    
  } catch (error) {
    console.error('Error creating content pages:', error);
    process.exit(1);
  }
  
  process.exit(0);
}

// Run the script
createSampleContentPages();

