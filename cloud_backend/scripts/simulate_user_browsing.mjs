/**
 * Simulation of Real User Browsing Session
 * Mimics a visitor exploring the community gallery, toggling filters,
 * switching sorting, viewing post details, author profiles, and marketplace items.
 */

import mongoose from 'mongoose';

const API_BASE = 'https://nass-works.com/ai-api/api/v1';
const MONGODB_URI = 'mongodb://localhost:27017/ai_image_studio?retryWrites=false';

async function simulate() {
  console.log('====================================================');
  console.log('STARTING REALISTIC BROWSING SIMULATION');
  console.log(`Target: ${API_BASE}`);
  console.log('====================================================\n');

  await mongoose.connect(MONGODB_URI);
  const db = mongoose.connection.db;

  // Find sample post and user to test detail and profile lookups
  const sampleApprovedPost = await db.collection('generations').findOne({
    isPublic: true,
    moderationStatus: 'approved',
  });
  const sampleUser = await db.collection('users').findOne({
    isPublicProfile: true,
  });

  const samplePostId = sampleApprovedPost?._id?.toString() || '6ab80d011d86811b8756bd6e';
  const sampleUsername = sampleUser?.username || 'testuser822476';

  await mongoose.disconnect();

  const browsingActions = [
    // 1. Initial Gallery Landing
    { name: '1. Land on /gallery (Default Recent)', url: `${API_BASE}/gallery?page=1&limit=24&sort=recent` },
    
    // 2. Filter tabs rapid clicking
    { name: '2. Click Filter: Images', url: `${API_BASE}/gallery?page=1&limit=24&sort=recent&mediaType=image` },
    { name: '3. Click Filter: Videos', url: `${API_BASE}/gallery?page=1&limit=24&sort=recent&mediaType=video` },
    { name: '4. Click Filter: Audio', url: `${API_BASE}/gallery?page=1&limit=24&sort=recent&mediaType=audio` },
    { name: '5. Click Filter: All', url: `${API_BASE}/gallery?page=1&limit=24&sort=recent` },

    // 3. Sort toggle clicking
    { name: '6. Switch Sort: Popular', url: `${API_BASE}/gallery?page=1&limit=24&sort=popular` },
    { name: '7. Filter Images + Popular', url: `${API_BASE}/gallery?page=1&limit=24&sort=popular&mediaType=image` },
    { name: '8. Filter Videos + Popular', url: `${API_BASE}/gallery?page=1&limit=24&sort=popular&mediaType=video` },
    { name: '9. Switch Sort: Recent again', url: `${API_BASE}/gallery?page=1&limit=24&sort=recent` },

    // 4. Pagination
    { name: '10. Paginate Page 2', url: `${API_BASE}/gallery?page=2&limit=24&sort=recent` },
    { name: '11. Paginate Page 3', url: `${API_BASE}/gallery?page=3&limit=24&sort=recent` },
    { name: '12. Back to Page 1', url: `${API_BASE}/gallery?page=1&limit=24&sort=recent` },

    // 5. Click through Single Post Detail
    { name: '13. Open Post Detail View', url: `${API_BASE}/gallery/${samplePostId}` },
    { name: '14. Repeat View (Refresh detail)', url: `${API_BASE}/gallery/${samplePostId}` },

    // 6. Creator Public Profile & Gallery
    { name: '15. View Creator Public Profile', url: `${API_BASE}/users/${sampleUsername}/public` },
    { name: '16. View Creator Gallery Feed', url: `${API_BASE}/gallery/user/${sampleUsername}` },
    { name: '17. Filter Creator Videos', url: `${API_BASE}/gallery/user/${sampleUsername}?mediaType=video` },

    // 7. Sibling Public Routes (Navigating across app tabs)
    { name: '18. Browse Models Catalog', url: `${API_BASE}/models` },
    { name: '19. Browse Compatibility Matrix', url: `${API_BASE}/models/compatibility/matrix` },
    { name: '20. Browse GPU Marketplace Offers', url: `${API_BASE}/gpu/offers` },
    { name: '21. Browse GPU Recommended', url: `${API_BASE}/gpu/recommended` },
    { name: '22. Fetch Pricing Config', url: `${API_BASE}/pricing/config` },
    { name: '23. App Health Check Ping', url: `${API_BASE}/health` },

    // 8. Return to Gallery for more browsing
    { name: '24. Return to Gallery (Recent)', url: `${API_BASE}/gallery?page=1&limit=24&sort=recent` },
    { name: '25. Rapid Filter: Images again', url: `${API_BASE}/gallery?page=1&limit=24&sort=recent&mediaType=image` },
    { name: '26. Rapid Filter: Popular again', url: `${API_BASE}/gallery?page=1&limit=24&sort=popular&mediaType=image` },
    { name: '27. Open another detail view', url: `${API_BASE}/gallery/${samplePostId}` },
    { name: '28. Paginate Popular Page 2', url: `${API_BASE}/gallery?page=2&limit=24&sort=popular` },
  ];

  let passedCount = 0;
  let rateLimitHit = false;

  console.log(`Executing ${browsingActions.length} browsing requests in rapid succession...\n`);

  for (const action of browsingActions) {
    const startTime = Date.now();
    try {
      const res = await fetch(action.url);
      const elapsed = Date.now() - startTime;
      const rlLimit = res.headers.get('ratelimit-limit') || 'N/A';
      const rlRemaining = res.headers.get('ratelimit-remaining') || 'N/A';
      const rlReset = res.headers.get('ratelimit-reset') || 'N/A';

      if (res.status === 429) {
        rateLimitHit = true;
        console.error(`❌ [429 TOO MANY REQUESTS] ${action.name} (${elapsed}ms)`);
        console.error(`   URL: ${action.url}`);
        console.error(`   Headers: limit=${rlLimit}, remaining=${rlRemaining}, reset=${rlReset}s`);
      } else {
        passedCount++;
        console.log(`✓ [HTTP ${res.status}] ${action.name} (${elapsed}ms) [RL: ${rlRemaining}/${rlLimit} left, reset: ${rlReset}s]`);
      }
    } catch (err) {
      console.error(`❌ [NETWORK ERROR] ${action.name}: ${err.message}`);
    }

    // Small realistic human inter-click delay (60ms)
    await new Promise((r) => setTimeout(r, 60));
  }

  console.log('\n====================================================');
  console.log('BROWSING SIMULATION RESULTS:');
  console.log(`Total Requests: ${browsingActions.length}`);
  console.log(`Successful (Non-429): ${passedCount}`);
  console.log(`429 Throttled: ${rateLimitHit ? 'YES' : 'NO (0)'}`);
  console.log('====================================================');

  if (rateLimitHit) {
    process.exit(1);
  }
}

simulate().catch((err) => {
  console.error('Simulation Fatal Error:', err);
  process.exit(1);
});
