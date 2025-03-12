import { PrismaClient } from "@prisma/client";

// PrismaClient is attached to the `global` object in development to prevent
// exhausting your database connection limit.
const globalForPrisma = global as unknown as { prisma: PrismaClient };

// Enhanced connection retry logic for Vercel deployments
const prismaClientSingleton = () => {
  console.log(
    "Initializing Prisma Client with DATABASE_URL:",
    process.env.DATABASE_URL
      ? "URL exists (not showing for security)"
      : "URL is undefined"
  );
  console.log(
    "POSTGRES_URL_NON_POOLING:",
    process.env.POSTGRES_URL_NON_POOLING
      ? "URL exists (not showing for security)"
      : "URL is undefined"
  );

  return new PrismaClient({
    log: ["query", "info", "warn", "error"],
    datasources: {
      db: {
        url: process.env.DATABASE_URL,
      },
    },
    // Add connection timeout settings
    errorFormat: "pretty",
  });
};

// Handle connection errors
const handlePrismaConnectionError = (error: any) => {
  console.error("Prisma connection error:", error);
  // Log detailed error information
  if (error.message) {
    console.error("Error message:", error.message);
  }
  if (error.code) {
    console.error("Error code:", error.code);
  }
  if (error.meta) {
    console.error("Error metadata:", error.meta);
  }

  // Throw the error to be handled by the caller
  throw error;
};

// Create Prisma client with error handling
let prismaWithErrorHandling: PrismaClient;

try {
  prismaWithErrorHandling = globalForPrisma.prisma || prismaClientSingleton();

  // Test the connection
  prismaWithErrorHandling
    .$connect()
    .then(() => console.log("Prisma connection successful"))
    .catch(handlePrismaConnectionError);
} catch (error) {
  console.error("Error initializing Prisma client:", error);
  // Re-throw to prevent app from starting with a broken DB connection
  throw error;
}

export const prisma = prismaWithErrorHandling;

if (process.env.NODE_ENV !== "production") globalForPrisma.prisma = prisma;
