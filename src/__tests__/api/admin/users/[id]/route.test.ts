import { mockPrisma } from "../../../../helpers/prisma-mock";
import {
  createMockRequest,
  mockAuthenticatedSession,
  mockUnauthenticatedSession,
} from "../../../../helpers/api-test-helpers";
import { NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";

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
      const response = {
        status: options.status,
        json: async () => data,
        ...data,
      };
      return response;
    }),
  },
}));

// Mock route module and authOptions to prevent NextAuth initialization
jest.mock("@/app/api/auth/[...nextauth]/route", () => ({
  authOptions: {},
}));

// Import the route handler - this should now work because we've mocked the dependencies
import { DELETE } from "@/app/api/admin/users/[id]/route";

describe("Admin Users [id] API", () => {
  // Reset all mocks before each test
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("DELETE /api/admin/users/[id]", () => {
    it("should return 401 if user is not authenticated", async () => {
      // Mock unauthenticated session
      mockUnauthenticatedSession();

      const req = createMockRequest({
        method: "DELETE",
      });

      const context = { params: { id: "test-user-id" } };

      const response = await DELETE(req as any, context);
      expect(response.status).toBe(401);

      const data = await response.json();
      expect(data.success).toBe(false);
      expect(data.message).toBe("Unauthorized");
    });

    it("should return 401 if user is not an admin", async () => {
      // Mock authenticated session but not as admin
      mockAuthenticatedSession("USER");

      const req = createMockRequest({
        method: "DELETE",
      });

      const context = { params: { id: "test-user-id" } };

      const response = await DELETE(req as any, context);
      expect(response.status).toBe(401);

      const data = await response.json();
      expect(data.success).toBe(false);
      expect(data.message).toBe("Unauthorized");
    });

    it("should delete user successfully", async () => {
      // Mock admin session
      mockAuthenticatedSession("ADMIN");

      // Mock successful user deletion
      mockPrisma.user.delete.mockResolvedValueOnce({
        id: "test-user-id",
        name: "Test User",
        email: "test@example.com",
      });

      const req = createMockRequest({
        method: "DELETE",
      });

      const context = { params: { id: "test-user-id" } };

      const response = await DELETE(req as any, context);
      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data.success).toBe(true);

      // Verify Prisma was called with correct parameters
      expect(mockPrisma.user.delete).toHaveBeenCalledWith({
        where: { id: "test-user-id" },
      });
    });

    it("should handle database errors", async () => {
      // Mock admin session
      mockAuthenticatedSession("ADMIN");

      // Mock database error
      mockPrisma.user.delete.mockRejectedValueOnce(new Error("Database error"));

      const req = createMockRequest({
        method: "DELETE",
      });

      const context = { params: { id: "test-user-id" } };

      const response = await DELETE(req as any, context);
      expect(response.status).toBe(500);

      const data = await response.json();
      expect(data.success).toBe(false);
      expect(data.message).toBe("Failed to delete user");
    });
  });
});
