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
    "DIRECT_URL:",
    process.env.DIRECT_URL
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
    errorFormat: "pretty",
  });
};

// Simple client without connection testing to avoid initialization errors
export const prisma = globalForPrisma.prisma || prismaClientSingleton();

if (process.env.NODE_ENV !== "production") globalForPrisma.prisma = prisma;
