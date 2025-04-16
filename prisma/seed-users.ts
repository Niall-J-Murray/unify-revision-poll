// Example structure for prisma/seed-extra.ts
import { PrismaClient, Prisma } from "@prisma/client";

const prisma = new PrismaClient();

async function seedExtraData() {
  console.log("🌱 Starting extra seeding (test users, features, votes)...");

  // Define adminEmail here
  const adminEmail = "niall.murray.dev@gmail.com";

  // --- Paste the removed code here ---
  // Create some regular users (using upsert)
  const users: Prisma.UserCreateInput[] = [
    /* ... */
  ];
  if (users.length > 0) {
    for (const _user of users) {
      /* await prisma.user.upsert(...) */
    }
  }

  // Get users (ensure adminEmail is defined or retrieved if needed)
  const adminUser = await prisma.user.findUnique({
    where: { email: adminEmail },
  });
  const johnUser = await prisma.user.findUnique({
    where: { email: "john@example.com" },
  });
  const janeUser = await prisma.user.findUnique({
    where: { email: "jane@example.com" },
  });

  if (!adminUser || !johnUser || !janeUser) {
    console.warn("One or more base users not found, skipping some extra data.");
    // Decide how to handle this - maybe skip feature/vote creation
  } else {
    // Create various feature requests (using upsert)
    const featureRequests: Prisma.FeatureRequestCreateInput[] = [
      /* ... using adminUser.id etc ... */
    ];
    if (featureRequests.length > 0) {
      for (const _request of featureRequests) {
        /* const featureRequest = await prisma.featureRequest.upsert(...) */
      }
    }
    // Create activities for features
    // ...

    // Add some votes (using upsert)
    const allFeatureRequests = await prisma.featureRequest.findMany();
    const _allUsers = await prisma.user.findMany();
    for (const _request of allFeatureRequests) {
      /* ... loop through voters ... await prisma.vote.upsert(...) ... */
    }
    // Create activities for votes
    // ...
  }

  // --- End of pasted code ---

  console.log("🌱 Extra seeding finished.");
}

seedExtraData()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
