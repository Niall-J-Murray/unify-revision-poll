import { NextResponse } from "next/server";
import { mockPrisma } from "../../../helpers/prisma-mock";
import { getServerSession } from "next-auth/next";
import { createMockRequest } from "../../../helpers/api-test-helpers";

// Mock dependencies
jest.mock("next-auth/next", () => ({
  getServerSession: jest.fn(),
}));

jest.mock("@/lib/prisma", () => ({
  prisma: mockPrisma,
}));

// Mock NextResponse
jest.mock("next/server", () => ({
  NextResponse: {
    json: jest.fn((data, options = { status: 200 }) => {
      return {
        data,
        status: options.status,
        json: async () => data,
      };
    }),
  },
}));

// Mock the auth options to prevent NextAuth initialization
jest.mock("@/app/api/auth/[...nextauth]/route", () => ({
  authOptions: {},
}));

// Import the actual route handlers
import { GET, PUT } from "@/app/api/user/profile/route";

// Mock console.log and console.error to avoid noisy test output
jest.spyOn(console, "log").mockImplementation(() => {});
jest.spyOn(console, "error").mockImplementation(() => {});

describe("User Profile API", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("GET /api/user/profile", () => {
    it("should return 401 if user is not authenticated", async () => {
      // Mock unauthenticated session
      (getServerSession as jest.Mock).mockResolvedValueOnce(null);

      // Call the endpoint with a mock request
      const req = createMockRequest({});
      const response = await GET(req as any);

      // Assertions
      expect(response.status).toBe(401);
      expect(response.data.success).toBe(false);
      expect(response.data.message).toBe("Unauthorized");
      expect(mockPrisma.user.findUnique).not.toHaveBeenCalled();
    });

    it("should return 404 if user is not found", async () => {
      // Mock authenticated session
      (getServerSession as jest.Mock).mockResolvedValueOnce({
        user: { email: "user@example.com" },
      });

      // Mock user not found
      mockPrisma.user.findUnique.mockResolvedValueOnce(null);

      // Call the endpoint with a mock request
      const req = createMockRequest({});
      const response = await GET(req as any);

      // Assertions
      expect(response.status).toBe(404);
      expect(response.data.success).toBe(false);
      expect(response.data.message).toBe("User not found");
      expect(mockPrisma.user.findUnique).toHaveBeenCalledWith({
        where: { email: "user@example.com" },
        select: {
          id: true,
          name: true,
          email: true,
          emailVerified: true,
          image: true,
          role: true,
          createdAt: true,
        },
      });
    });

    it("should return user profile successfully", async () => {
      // Mock authenticated session
      (getServerSession as jest.Mock).mockResolvedValueOnce({
        user: { email: "user@example.com" },
      });

      // Mock user found
      const mockUser = {
        id: "user-1",
        name: "Test User",
        email: "user@example.com",
        emailVerified: new Date(),
        image: "https://example.com/avatar.jpg",
        role: "USER",
        createdAt: new Date(),
      };
      mockPrisma.user.findUnique.mockResolvedValueOnce(mockUser);

      // Call the endpoint with a mock request
      const req = createMockRequest({});
      const response = await GET(req as any);

      // Assertions
      expect(response.status).toBe(200);
      expect(response.data.success).toBe(true);
      expect(response.data.user).toEqual(mockUser);
    });

    it("should handle database errors", async () => {
      // Mock authenticated session
      (getServerSession as jest.Mock).mockResolvedValueOnce({
        user: { email: "user@example.com" },
      });

      // Mock database error
      mockPrisma.user.findUnique.mockRejectedValueOnce(
        new Error("Database error")
      );

      // Call the endpoint with a mock request
      const req = createMockRequest({});
      const response = await GET(req as any);

      // Assertions
      expect(response.status).toBe(500);
      expect(response.data.success).toBe(false);
      expect(response.data.message).toBe("Failed to fetch profile");
    });
  });

  describe("PUT /api/user/profile", () => {
    it("should return 401 if user is not authenticated", async () => {
      // Mock unauthenticated session
      (getServerSession as jest.Mock).mockResolvedValueOnce(null);

      // Create mock request
      const req = createMockRequest({
        method: "PUT",
        body: {
          name: "Updated Name",
        },
      });

      // Call the endpoint
      const response = await PUT(req as any);

      // Assertions
      expect(response.status).toBe(401);
      expect(response.data.success).toBe(false);
      expect(response.data.message).toBe("Unauthorized");
      expect(mockPrisma.user.update).not.toHaveBeenCalled();
    });

    it("should update user profile successfully", async () => {
      // Mock authenticated session
      (getServerSession as jest.Mock).mockResolvedValueOnce({
        user: { email: "user@example.com" },
      });

      // Mock user update
      const updatedUser = {
        id: "user-1",
        name: "Updated Name",
        email: "user@example.com",
        emailVerified: new Date(),
        image: "https://example.com/avatar.jpg",
        role: "USER",
      };
      mockPrisma.user.update.mockResolvedValueOnce(updatedUser);

      // Create mock request
      const req = createMockRequest({
        method: "PUT",
        body: {
          name: "Updated Name",
        },
      });

      // Call the endpoint
      const response = await PUT(req as any);

      // Assertions
      expect(response.status).toBe(200);
      expect(response.data.success).toBe(true);
      expect(response.data.user).toEqual(updatedUser);
      expect(mockPrisma.user.update).toHaveBeenCalledWith({
        where: { email: "user@example.com" },
        data: { name: "Updated Name" },
        select: {
          id: true,
          name: true,
          email: true,
          emailVerified: true,
          image: true,
          role: true,
        },
      });
    });

    it("should handle database errors", async () => {
      // Mock authenticated session
      (getServerSession as jest.Mock).mockResolvedValueOnce({
        user: { email: "user@example.com" },
      });

      // Mock database error
      mockPrisma.user.update.mockRejectedValueOnce(new Error("Database error"));

      // Create mock request
      const req = createMockRequest({
        method: "PUT",
        body: {
          name: "Updated Name",
        },
      });

      // Call the endpoint
      const response = await PUT(req as any);

      // Assertions
      expect(response.status).toBe(500);
      expect(response.data.success).toBe(false);
      expect(response.data.message).toBe("Failed to update profile");
    });
  });
});
