import { PrismaClient } from "@prisma/client";
import bcrypt from "bcrypt";

const prisma = new PrismaClient();

async function main() {
  console.log("🌱 Starting seeding...");

  const userCount = await prisma.user.count();

  if (userCount === 0) {
    console.log("No users found. Creating initial admin user...");

    const adminEmail = "niall.murray.dev@gmail.com";
    const adminName = "Murrmin";
    const plainPassword = "Murrpass321!";

    // Hash the password
    const saltRounds = 10;
    const hashedPassword = await bcrypt.hash(plainPassword, saltRounds);

    await prisma.user.create({
      data: {
        email: adminEmail,
        name: adminName,
        password: hashedPassword,
        emailVerified: new Date(), // Mark email as verified
        // Add any other required fields for the User model with default/initial values
        // e.g., role: 'ADMIN' if you have a role field
      },
    });
    console.log(
      `Admin user ${adminName} (${adminEmail}) created successfully.`
    );
  } else {
    console.log(
      `Database already contains ${userCount} users. Skipping admin user creation.`
    );
  }

  // Create some regular users
  const users = [
    {
      name: "John Doe",
      email: "john@example.com",
      password: "password123",
    },
    {
      name: "Jane Smith",
      email: "jane@example.com",
      password: "password123",
    },
    {
      name: "Bob Wilson",
      email: "bob@example.com",
      password: "password123",
    },
  ];

  for (const user of users) {
    await prisma.user.upsert({
      where: { email: user.email },
      update: {
        name: user.name,
        password: await bcrypt.hash(user.password, 10),
        emailVerified: new Date(),
      },
      create: {
        name: user.name,
        email: user.email,
        password: await bcrypt.hash(user.password, 10),
        role: "USER",
        emailVerified: new Date(),
      },
    });
  }

  // Get all users for creating feature requests
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
    throw new Error("Failed to create users");
  }

  // Create various feature requests
  const featureRequests = [
    {
      title: "Mobile App Support",
      description:
        "Develop a mobile app version of Unify Ordering for iOS and Android",
      status: "IN_PROGRESS",
      userId: adminUser.id,
    },
    {
      title: "Dark Mode Support",
      description: "Add dark mode theme support across all pages",
      status: "COMPLETED",
      userId: johnUser.id,
    },
    {
      title: "Bulk Order Management",
      description: "Allow users to manage multiple orders simultaneously",
      status: "PENDING",
      userId: janeUser.id,
    },
    {
      title: "Advanced Analytics Dashboard",
      description: "Provide detailed analytics and reporting features",
      status: "ACCEPTED",
      userId: johnUser.id,
    },
    {
      title: "Integration with Payment Gateways",
      description: "Add support for multiple payment providers",
      status: "PENDING",
      userId: adminUser.id,
    },
  ];

  for (const request of featureRequests) {
    const featureRequest = await prisma.featureRequest.upsert({
      where: {
        title_userId: {
          title: request.title,
          userId: request.userId,
        },
      },
      update: {
        description: request.description,
        status: request.status,
      },
      create: {
        title: request.title,
        description: request.description,
        status: request.status,
        userId: request.userId,
      },
    });

    // Create an activity for the feature request creation
    await prisma.activity.create({
      data: {
        type: "created",
        userId: request.userId,
        featureRequestId: featureRequest.id,
      },
    });
  }

  // Add some votes
  const allFeatureRequests = await prisma.featureRequest.findMany();
  const allUsers = await prisma.user.findMany();

  // Randomly distribute some votes
  for (const request of allFeatureRequests) {
    // Randomly select 1-3 users to vote on each request
    const voterCount = Math.floor(Math.random() * 3) + 1;
    const shuffledUsers = allUsers.sort(() => 0.5 - Math.random());
    const voters = shuffledUsers.slice(0, voterCount);

    for (const voter of voters) {
      await prisma.vote.upsert({
        where: {
          userId_featureRequestId: {
            userId: voter.id,
            featureRequestId: request.id,
          },
        },
        update: {},
        create: {
          userId: voter.id,
          featureRequestId: request.id,
        },
      });

      // Create an activity for the vote
      await prisma.activity.create({
        data: {
          type: "voted",
          userId: voter.id,
          featureRequestId: request.id,
        },
      });
    }
  }

  // Create a user
  const user = await prisma.user.create({
    data: {
      name: "John Doe",
      email: "john.doe@example.com",
      emailVerified: new Date(),
      createdAt: new Date(),
    },
  });

  // Create feature requests
  const featureRequest1 = await prisma.featureRequest.create({
    data: {
      title: "Feature Request 1",
      description: "Description for feature request 1",
      createdAt: new Date(),
      userId: user.id,
    },
  });

  const featureRequest2 = await prisma.featureRequest.create({
    data: {
      title: "Feature Request 2",
      description: "Description for feature request 2",
      createdAt: new Date(),
      userId: user.id,
    },
  });

  // Create activities
  await prisma.activity.createMany({
    data: [
      {
        userId: user.id,
        featureRequestId: featureRequest1.id,
        type: "created",
        createdAt: new Date(),
      },
      {
        userId: user.id,
        featureRequestId: featureRequest2.id,
        type: "voted",
        createdAt: new Date(),
      },
    ],
  });

  console.log("🌱 Seeding finished.");
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
