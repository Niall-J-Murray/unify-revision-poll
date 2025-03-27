import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

async function testConnection() {
  try {
    // Try to connect to the database
    await prisma.$connect();
    console.log("Successfully connected to the database!");

    // Try a simple query
    const result = await prisma.$queryRaw`SELECT 1`;
    console.log("Query result:", result);

    await prisma.$disconnect();
  } catch (error) {
    console.error("Failed to connect to the database:", error);
  }
}

testConnection();
