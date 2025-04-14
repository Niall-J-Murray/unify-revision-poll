import { PrismaClient } from "@prisma/client";
import bcrypt from "bcrypt";

const prisma = new PrismaClient();

// Define adminEmail outside the conditional block
const adminEmail = "niall.murray.dev@gmail.com";

async function main() {
  console.log("🌱 Starting seeding...");

  // Check if the specific admin user already exists
  const existingAdmin = await prisma.user.findUnique({
    where: { email: adminEmail },
  });

  // if (userCount === 0) { // Old logic
  if (!existingAdmin) {
    // New logic: Create only if admin doesn't exist
    console.log(`Admin user (${adminEmail}) not found. Creating admin user...`);

    // Use the constant defined above
    const adminName = "Murrmin";
    const plainPassword = "Murrpass321!"; // Make sure this is secure or ideally sourced from env vars

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
      `Admin user (${adminEmail}) already exists. Skipping admin user creation.`
    );
  }

  // --- REMOVED OTHER SEEDING LOGIC ---

  console.log("🌱 Seeding finished."); // Adjusted message slightly
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
