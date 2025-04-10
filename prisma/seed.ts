import { PrismaClient } from "@prisma/client";
import bcrypt from "bcrypt";

const prisma = new PrismaClient();

// Define adminEmail outside the conditional block
const adminEmail = "niall.murray.dev@gmail.com";

async function main() {
  console.log("🌱 Starting seeding...");

  const userCount = await prisma.user.count();

  if (userCount === 0) {
    console.log("No users found. Creating initial admin user...");

    // Use the constant defined above
    // const adminEmail = "niall.murray.dev@gmail.com";
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

  // --- REMOVED OTHER SEEDING LOGIC ---

  console.log("🌱 Seeding finished (Admin user only).");
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
