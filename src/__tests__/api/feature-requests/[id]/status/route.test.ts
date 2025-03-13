import { NextResponse } from "next/server";
import { mockPrisma } from "../../../../helpers/prisma-mock";
import { getServerSession } from "next-auth/next";
import { createMockRequest } from "../../../../helpers/api-test-helpers";

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

// Import the actual route handler
import { PATCH } from "@/app/api/feature-requests/[id]/status/route";

describe("Feature Request Status API", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("PATCH /api/feature-requests/[id]/status", () => {
    it("should return 401 if user is not authenticated", async () => {
      // Mock unauthenticated session
      (getServerSession as jest.Mock).mockResolvedValueOnce(null);

      // Create mock request
      const req = createMockRequest({
        method: "PATCH",
        body: {
          status: "IN_PROGRESS",
        },
      });

      // Call the endpoint
      const response = await PATCH(req as any, {
        params: { id: "feature-1" },
      });

      // Assertions
      expect(response.status).toBe(401);
      expect(response.data.success).toBe(false);
      expect(response.data.message).toBe("Unauthorized");
      expect(mockPrisma.featureRequest.update).not.toHaveBeenCalled();
    });

    it("should return 401 if user is not an admin", async () => {
      // Mock authenticated session but not admin
      (getServerSession as jest.Mock).mockResolvedValueOnce({
        user: { id: "user-1", email: "user@example.com", role: "USER" },
      });

      // Create mock request
      const req = createMockRequest({
        method: "PATCH",
        body: {
          status: "IN_PROGRESS",
        },
      });

      // Call the endpoint
      const response = await PATCH(req as any, {
        params: { id: "feature-1" },
      });

      // Assertions
      expect(response.status).toBe(401);
      expect(response.data.success).toBe(false);
      expect(response.data.message).toBe("Unauthorized");
      expect(mockPrisma.featureRequest.update).not.toHaveBeenCalled();
    });

    it("should return 400 if status is invalid", async () => {
      // Mock authenticated session with admin role
      (getServerSession as jest.Mock).mockResolvedValueOnce({
        user: { id: "admin-1", email: "admin@example.com", role: "ADMIN" },
      });

      // Create mock request with invalid status
      const req = createMockRequest({
        method: "PATCH",
        body: {
          status: "INVALID_STATUS",
        },
      });

      // Call the endpoint
      const response = await PATCH(req as any, {
        params: { id: "feature-1" },
      });

      // Assertions
      expect(response.status).toBe(400);
      expect(response.data.success).toBe(false);
      expect(response.data.message).toBe("Invalid status");
      expect(mockPrisma.featureRequest.update).not.toHaveBeenCalled();
    });

    it.each(["PENDING", "IN_PROGRESS", "COMPLETED", "REJECTED"])(
      "should update status to %s successfully",
      async (status) => {
        // Mock authenticated session with admin role
        (getServerSession as jest.Mock).mockResolvedValueOnce({
          user: { id: "admin-1", email: "admin@example.com", role: "ADMIN" },
        });

        // Mock feature request update
        mockPrisma.featureRequest.update.mockResolvedValueOnce({
          id: "feature-1",
          title: "Feature Title",
          description: "Feature Description",
          status,
        });

        // Create mock request
        const req = createMockRequest({
          method: "PATCH",
          body: { status },
        });

        // Call the endpoint
        const response = await PATCH(req as any, {
          params: { id: "feature-1" },
        });

        // Assertions
        expect(response.status).toBe(200);
        expect(response.data.success).toBe(true);
        expect(response.data.featureRequest).toBeDefined();
        expect(response.data.featureRequest.status).toBe(status);
        expect(mockPrisma.featureRequest.update).toHaveBeenCalledWith({
          where: { id: "feature-1" },
          data: { status },
        });
      }
    );

    it("should handle database errors", async () => {
      // Mock authenticated session with admin role
      (getServerSession as jest.Mock).mockResolvedValueOnce({
        user: { id: "admin-1", email: "admin@example.com", role: "ADMIN" },
      });

      // Mock feature request update to throw error
      mockPrisma.featureRequest.update.mockRejectedValueOnce(
        new Error("Database error")
      );

      // Create mock request
      const req = createMockRequest({
        method: "PATCH",
        body: {
          status: "IN_PROGRESS",
        },
      });

      // Call the endpoint
      const response = await PATCH(req as any, {
        params: { id: "feature-1" },
      });

      // Assertions
      expect(response.status).toBe(500);
      expect(response.data.success).toBe(false);
      expect(response.data.message).toBe("Failed to update status");
    });
  });
});
