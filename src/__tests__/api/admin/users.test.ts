// Import the helpers first
import { mockPrisma } from "../../helpers/prisma-mock";
import {
  createMockRequest,
  mockAuthenticatedSession,
  mockUnauthenticatedSession,
  assertResponse,
} from "../../helpers/api-test-helpers";
import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { PrismaClient } from "@prisma/client";
import { createMockNextRequest } from "../../helpers/next-request-helpers";

// Need to move the jest.mock calls to the top before any imports
jest.mock("next-auth/next");
jest.mock("@/lib/prisma");

// Mock dependencies
jest.mock("@/lib/prisma", () => ({
  prisma: mockPrisma,
}));

// Mock NextAuth
jest.mock("next-auth/next", () => ({
  getServerSession: jest.fn(),
}));

// Mock NextResponse and NextRequest
jest.mock("next/server", () => ({
  NextResponse: {
    json: jest.fn((data, options = { status: 200 }) => {
      const response = {
        status: options.status,
        json: async () => data,
        ...data,
      };
      return response;
    }),
  },
}));

// Mock authOptions
jest.mock("@/app/api/auth/[...nextauth]/route", () => ({
  authOptions: {
    providers: [],
    callbacks: {},
  },
}));

// Import the actual route handlers
import { GET, POST } from "@/app/api/admin/users/route";

// Mock Prisma client
const mockPrismaClient = {
  user: {
    findMany: jest.fn(),
    findUnique: jest.fn(),
    create: jest.fn(),
  },
};

jest.mock("@prisma/client", () => ({
  PrismaClient: jest.fn().mockImplementation(() => mockPrismaClient),
}));

describe("Admin Users API", () => {
  // Reset all mocks before each test
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("GET /api/admin/users", () => {
    it("should return 403 if user is not an admin", async () => {
      // Mock authenticated session but not as admin
      mockAuthenticatedSession("USER");

      const req = createMockNextRequest({});

      const response = await GET(req);
      expect(response.status).toBe(403);

      const data = await response.json();
      expect(data.success).toBe(false);
      expect(data.message).toBe("Unauthorized");
    });

    it("should return 403 if user is not authenticated", async () => {
      // Mock unauthenticated session
      mockUnauthenticatedSession();

      const req = createMockNextRequest({});

      const response = await GET(req);
      expect(response.status).toBe(403);

      const data = await response.json();
      expect(data.success).toBe(false);
      expect(data.message).toBe("Unauthorized");
    });

    it("should return a list of users for admin", async () => {
      // Mock admin session
      mockAuthenticatedSession("ADMIN");

      // Mock users data
      const mockUsers = [
        {
          id: "user-1",
          name: "Test User",
          email: "test@example.com",
          emailVerified: new Date(),
          role: "USER",
          createdAt: new Date(),
          updatedAt: new Date(),
          password: "$2a$10$mockhashedpassword",
        },
      ];

      mockPrisma.user.findMany.mockResolvedValueOnce(mockUsers);

      const req = createMockNextRequest({});

      const response = await GET(req);
      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data.success).toBe(true);
      expect(data.users).toEqual(mockUsers);

      // Verify Prisma was called with correct parameters
      expect(mockPrisma.user.findMany).toHaveBeenCalledWith({
        select: {
          id: true,
          name: true,
          email: true,
          emailVerified: true,
          role: true,
          createdAt: true,
        },
        orderBy: {
          createdAt: "desc",
        },
      });
    });

    it("should handle database errors", async () => {
      // Mock admin session
      mockAuthenticatedSession("ADMIN");

      // Mock database error
      mockPrisma.user.findMany.mockRejectedValueOnce(
        new Error("Database error")
      );

      const req = createMockNextRequest({});

      const response = await GET(req);
      expect(response.status).toBe(500);

      const data = await response.json();
      expect(data.success).toBe(false);
      expect(data.message).toBe("Failed to fetch users");
    });
  });

  describe("POST /api/admin/users", () => {
    it("should return 403 if user is not an admin", async () => {
      // Mock authenticated session but not as admin
      mockAuthenticatedSession("USER");

      const req = createMockNextRequest({
        method: "POST",
        body: {
          name: "New User",
          email: "newuser@example.com",
          password: "password123",
        },
      });

      const response = await POST(req);
      expect(response.status).toBe(403);

      const data = await response.json();
      expect(data.success).toBe(false);
      expect(data.message).toBe("Unauthorized");
    });

    it("should validate required fields", async () => {
      // Mock admin session
      mockAuthenticatedSession("ADMIN");

      const req = createMockNextRequest({
        method: "POST",
        body: {
          name: "New User",
          // Missing email and password
        },
      });

      const response = await POST(req);
      expect(response.status).toBe(400);

      const data = await response.json();
      expect(data.success).toBe(false);
      expect(data.message).toBe("Email and password are required");
    });

    it("should check for existing users", async () => {
      // Mock admin session
      mockAuthenticatedSession("ADMIN");

      // Mock existing user
      mockPrisma.user.findUnique.mockResolvedValueOnce({
        id: "existing-user",
        email: "existing@example.com",
      });

      const req = createMockNextRequest({
        method: "POST",
        body: {
          name: "New User",
          email: "existing@example.com",
          password: "password123",
        },
      });

      const response = await POST(req);
      expect(response.status).toBe(400);

      const data = await response.json();
      expect(data.success).toBe(false);
      expect(data.message).toBe("Email already in use");
    });

    it("should create a new user successfully", async () => {
      // Mock admin session
      mockAuthenticatedSession("ADMIN");

      // Mock no existing user
      mockPrisma.user.findUnique.mockResolvedValueOnce(null);

      // Mock user creation
      const mockNewUser = {
        id: "new-user",
        name: "New User",
        email: "newuser@example.com",
        role: "USER",
        emailVerified: new Date(),
        createdAt: new Date(),
      };

      mockPrisma.user.create.mockResolvedValueOnce(mockNewUser);

      const requestBody = {
        name: "New User",
        email: "newuser@example.com",
        password: "password123",
      };

      const req = createMockNextRequest({
        method: "POST",
        body: requestBody,
      });

      const response = await POST(req);
      expect(response.status).toBe(201);

      const data = await response.json();
      expect(data.success).toBe(true);
      expect(data.message).toBe("User created successfully");
      expect(data.user).toEqual({
        id: mockNewUser.id,
        name: mockNewUser.name,
        email: mockNewUser.email,
        role: mockNewUser.role,
      });
    });

    it("should handle database errors during creation", async () => {
      // Mock admin session
      mockAuthenticatedSession("ADMIN");

      // Mock no existing user
      mockPrisma.user.findUnique.mockResolvedValueOnce(null);

      // Mock database error during creation
      mockPrisma.user.create.mockRejectedValueOnce(new Error("Database error"));

      const requestBody = {
        name: "New User",
        email: "newuser@example.com",
        password: "password123",
      };

      const req = createMockNextRequest({
        method: "POST",
        body: requestBody,
      });

      const response = await POST(req);
      expect(response.status).toBe(500);

      const data = await response.json();
      expect(data.success).toBe(false);
      expect(data.message).toBe("Failed to create user");
    });
  });
});
