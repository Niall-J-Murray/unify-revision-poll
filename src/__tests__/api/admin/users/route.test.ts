import { NextResponse } from "next/server";
import { mockPrisma } from "../../../helpers/prisma-mock";
import { createMockRequest } from "../../../helpers/api-test-helpers";
import { getServerSession } from "next-auth/next";

// Mock dependencies
jest.mock("@/lib/prisma", () => ({
  prisma: mockPrisma,
}));

jest.mock("next-auth/next", () => ({
  getServerSession: jest.fn(),
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

// Mock console.error to avoid noise in tests
jest.spyOn(console, "error").mockImplementation(() => {});

// Import the route handlers after mocking dependencies
import { GET, POST } from "@/app/api/admin/users/route";

describe("Admin Users API", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("GET /api/admin/users", () => {
    it("should return 403 if user is not authenticated", async () => {
      // Mock unauthenticated session
      (getServerSession as jest.Mock).mockResolvedValueOnce(null);

      // Call the endpoint
      const req = createMockRequest({});
      const response = await GET(req as any);

      // Assertions
      expect(response.status).toBe(403);
      expect(response.data).toEqual({
        success: false,
        message: "Unauthorized",
      });
      expect(mockPrisma.user.findMany).not.toHaveBeenCalled();
    });

    it("should return 403 if user is not an admin", async () => {
      // Mock authenticated session but not admin
      (getServerSession as jest.Mock).mockResolvedValueOnce({
        user: { id: "user-123", role: "USER" },
      });

      // Call the endpoint
      const req = createMockRequest({});
      const response = await GET(req as any);

      // Assertions
      expect(response.status).toBe(403);
      expect(response.data).toEqual({
        success: false,
        message: "Unauthorized",
      });
      expect(mockPrisma.user.findMany).not.toHaveBeenCalled();
    });

    it("should return users list if user is admin", async () => {
      // Mock authenticated admin session
      (getServerSession as jest.Mock).mockResolvedValueOnce({
        user: { id: "admin-123", role: "ADMIN" },
      });

      // Mock users response
      const mockUsers = [
        {
          id: "user-1",
          name: "User 1",
          email: "user1@example.com",
          emailVerified: new Date(),
          role: "USER",
          createdAt: new Date(),
        },
        {
          id: "admin-123",
          name: "Admin User",
          email: "admin@example.com",
          emailVerified: new Date(),
          role: "ADMIN",
          createdAt: new Date(),
        },
      ];
      mockPrisma.user.findMany.mockResolvedValueOnce(mockUsers);

      // Call the endpoint
      const req = createMockRequest({});
      const response = await GET(req as any);

      // Assertions
      expect(response.status).toBe(200);
      expect(response.data).toEqual({
        success: true,
        users: mockUsers,
      });
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
      // Mock authenticated admin session
      (getServerSession as jest.Mock).mockResolvedValueOnce({
        user: { id: "admin-123", role: "ADMIN" },
      });

      // Mock database error
      mockPrisma.user.findMany.mockRejectedValueOnce(
        new Error("Database error")
      );

      // Call the endpoint
      const req = createMockRequest({});
      const response = await GET(req as any);

      // Assertions
      expect(response.status).toBe(500);
      expect(response.data).toEqual({
        success: false,
        message: "Failed to fetch users",
      });
    });
  });

  describe("POST /api/admin/users", () => {
    it("should return 403 if user is not authenticated", async () => {
      // Mock unauthenticated session
      (getServerSession as jest.Mock).mockResolvedValueOnce(null);

      // Call the endpoint
      const req = createMockRequest({
        method: "POST",
        body: {
          name: "New User",
          email: "newuser@example.com",
          password: "password123",
        },
      });
      const response = await POST(req as any);

      // Assertions
      expect(response.status).toBe(403);
      expect(response.data).toEqual({
        success: false,
        message: "Unauthorized",
      });
      expect(mockPrisma.user.create).not.toHaveBeenCalled();
    });

    it("should return 403 if user is not an admin", async () => {
      // Mock authenticated session but not admin
      (getServerSession as jest.Mock).mockResolvedValueOnce({
        user: { id: "user-123", role: "USER" },
      });

      // Call the endpoint
      const req = createMockRequest({
        method: "POST",
        body: {
          name: "New User",
          email: "newuser@example.com",
          password: "password123",
        },
      });
      const response = await POST(req as any);

      // Assertions
      expect(response.status).toBe(403);
      expect(response.data).toEqual({
        success: false,
        message: "Unauthorized",
      });
      expect(mockPrisma.user.create).not.toHaveBeenCalled();
    });

    it("should return 400 if email or password is missing", async () => {
      // Mock authenticated admin session
      (getServerSession as jest.Mock).mockResolvedValueOnce({
        user: { id: "admin-123", role: "ADMIN" },
      });

      // Call the endpoint with missing password
      const req = createMockRequest({
        method: "POST",
        body: {
          name: "New User",
          email: "newuser@example.com",
          // No password
        },
      });
      const response = await POST(req as any);

      // Assertions
      expect(response.status).toBe(400);
      expect(response.data).toEqual({
        success: false,
        message: "Email and password are required",
      });
      expect(mockPrisma.user.create).not.toHaveBeenCalled();
    });

    it("should return 400 if email is already in use", async () => {
      // Mock authenticated admin session
      (getServerSession as jest.Mock).mockResolvedValueOnce({
        user: { id: "admin-123", role: "ADMIN" },
      });

      // Mock existing user
      mockPrisma.user.findUnique.mockResolvedValueOnce({
        id: "existing-user",
        email: "existing@example.com",
      });

      // Call the endpoint
      const req = createMockRequest({
        method: "POST",
        body: {
          name: "New User",
          email: "existing@example.com",
          password: "password123",
        },
      });
      const response = await POST(req as any);

      // Assertions
      expect(response.status).toBe(400);
      expect(response.data).toEqual({
        success: false,
        message: "Email already in use",
      });
      expect(mockPrisma.user.create).not.toHaveBeenCalled();
    });

    it("should create a new user successfully", async () => {
      // Mock authenticated admin session
      (getServerSession as jest.Mock).mockResolvedValueOnce({
        user: { id: "admin-123", role: "ADMIN" },
      });

      // Mock email not in use
      mockPrisma.user.findUnique.mockResolvedValueOnce(null);

      // Mock user creation
      const newUser = {
        id: "new-user-123",
        name: "New User",
        email: "newuser@example.com",
        role: "USER",
      };
      mockPrisma.user.create.mockResolvedValueOnce(newUser);

      // Call the endpoint
      const req = createMockRequest({
        method: "POST",
        body: {
          name: "New User",
          email: "newuser@example.com",
          password: "password123",
        },
      });
      const response = await POST(req as any);

      // Assertions
      expect(response.status).toBe(201);
      expect(response.data).toEqual({
        success: true,
        message: "User created successfully",
        user: newUser,
      });
      expect(mockPrisma.user.create).toHaveBeenCalledWith({
        data: {
          name: "New User",
          email: "newuser@example.com",
          password: "password123", // In a real implementation, this should be hashed
          role: "USER",
          emailVerified: expect.any(Date),
        },
      });
    });

    it("should use custom role if provided", async () => {
      // Mock authenticated admin session
      (getServerSession as jest.Mock).mockResolvedValueOnce({
        user: { id: "admin-123", role: "ADMIN" },
      });

      // Mock email not in use
      mockPrisma.user.findUnique.mockResolvedValueOnce(null);

      // Mock user creation
      const newUser = {
        id: "new-admin-123",
        name: "New Admin",
        email: "newadmin@example.com",
        role: "ADMIN",
      };
      mockPrisma.user.create.mockResolvedValueOnce(newUser);

      // Call the endpoint with custom role
      const req = createMockRequest({
        method: "POST",
        body: {
          name: "New Admin",
          email: "newadmin@example.com",
          password: "password123",
          role: "ADMIN",
        },
      });
      const response = await POST(req as any);

      // Assertions
      expect(response.status).toBe(201);
      expect(response.data.user.role).toBe("ADMIN");
      expect(mockPrisma.user.create).toHaveBeenCalledWith({
        data: {
          name: "New Admin",
          email: "newadmin@example.com",
          password: "password123", // In a real implementation, this should be hashed
          role: "ADMIN",
          emailVerified: expect.any(Date),
        },
      });
    });

    it("should handle database errors", async () => {
      // Mock authenticated admin session
      (getServerSession as jest.Mock).mockResolvedValueOnce({
        user: { id: "admin-123", role: "ADMIN" },
      });

      // Mock email not in use
      mockPrisma.user.findUnique.mockResolvedValueOnce(null);

      // Mock database error
      mockPrisma.user.create.mockRejectedValueOnce(new Error("Database error"));

      // Call the endpoint
      const req = createMockRequest({
        method: "POST",
        body: {
          name: "New User",
          email: "newuser@example.com",
          password: "password123",
        },
      });
      const response = await POST(req as any);

      // Assertions
      expect(response.status).toBe(500);
      expect(response.data).toEqual({
        success: false,
        message: "Failed to create user",
      });
    });
  });
});
