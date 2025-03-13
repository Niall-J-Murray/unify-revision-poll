import { NextResponse } from "next/server";
import { mockPrisma } from "../../../helpers/prisma-mock";
import { createMockRequest } from "../../../helpers/api-test-helpers";
import {
  createMockAuthSession,
  createMockAdminSession,
  createMockUnauthSession,
} from "../../../helpers/auth-helpers";

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

// Mock auth options to prevent NextAuth initialization
jest.mock("@/app/api/auth/[...nextauth]/route", () => ({
  authOptions: {},
}));

// Import the route handlers after mocking dependencies
import { PUT, DELETE } from "@/app/api/feature-requests/[id]/route";
import { getServerSession } from "next-auth/next";

describe("Feature Request [id] API", () => {
  const mockUser = {
    id: "user-123",
    name: "Test User",
    email: "test@example.com",
    role: "user",
  };

  const mockFeatureRequest = {
    id: "fr-123",
    title: "Test Feature Request",
    description: "This is a test feature request",
    userId: "user-123",
    user: {
      name: "Test User",
      email: "test@example.com",
    },
    status: "pending",
    votes: [],
    activities: [],
  };

  const mockRequestWithVotes = {
    id: "fr-456",
    title: "Feature Request with Votes",
    description: "This feature request has votes",
    userId: "user-123",
    status: "pending",
    votes: [{ userId: "voter-1" }, { userId: "voter-2" }],
    activities: [],
  };

  const mockRequestFromAnotherUser = {
    id: "fr-789",
    title: "Another User's Request",
    description: "This belongs to another user",
    userId: "another-user-456",
    status: "pending",
    votes: [],
    activities: [],
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("PUT handler", () => {
    it("should return 401 if user is not authenticated", async () => {
      // Setup
      (getServerSession as jest.Mock).mockResolvedValue(
        createMockUnauthSession()
      );

      const req = createMockRequest({
        method: "PUT",
        body: { title: "Updated Title", description: "Updated Description" },
      });
      const response = await PUT(
        req as any,
        { params: { id: "fr-123" } } as any
      );

      // Assertions
      expect(response.status).toBe(401);
      expect(response.data.message).toBe("Unauthorized");
      expect(mockPrisma.featureRequest.findUnique).not.toHaveBeenCalled();
    });

    it("should return 404 if feature request doesn't exist", async () => {
      // Setup
      (getServerSession as jest.Mock).mockResolvedValue(
        createMockAuthSession(mockUser)
      );
      mockPrisma.featureRequest.findUnique.mockResolvedValue(null);

      const req = createMockRequest({
        method: "PUT",
        body: { title: "Updated Title", description: "Updated Description" },
      });
      const response = await PUT(
        req as any,
        { params: { id: "non-existent-id" } } as any
      );

      // Assertions
      expect(response.status).toBe(404);
      expect(response.data.message).toBe("Feature request not found");
      expect(mockPrisma.featureRequest.update).not.toHaveBeenCalled();
    });

    it("should return 403 if user is not the owner", async () => {
      // Setup
      (getServerSession as jest.Mock).mockResolvedValue(
        createMockAuthSession(mockUser)
      );
      mockPrisma.featureRequest.findUnique.mockResolvedValue(
        mockRequestFromAnotherUser
      );

      const req = createMockRequest({
        method: "PUT",
        body: { title: "Updated Title", description: "Updated Description" },
      });
      const response = await PUT(
        req as any,
        { params: { id: "fr-789" } } as any
      );

      // Assertions
      expect(response.status).toBe(403);
      expect(response.data.message).toBe("You can only edit your own requests");
      expect(mockPrisma.featureRequest.update).not.toHaveBeenCalled();
    });

    it("should return 403 if feature request has votes", async () => {
      // Setup
      (getServerSession as jest.Mock).mockResolvedValue(
        createMockAuthSession(mockUser)
      );
      mockPrisma.featureRequest.findUnique.mockResolvedValue(
        mockRequestWithVotes
      );

      const req = createMockRequest({
        method: "PUT",
        body: { title: "Updated Title", description: "Updated Description" },
      });
      const response = await PUT(
        req as any,
        { params: { id: "fr-456" } } as any
      );

      // Assertions
      expect(response.status).toBe(403);
      expect(response.data.message).toBe(
        "Cannot edit a request that has votes"
      );
      expect(mockPrisma.featureRequest.update).not.toHaveBeenCalled();
    });

    it("should update the feature request successfully", async () => {
      // Setup
      (getServerSession as jest.Mock).mockResolvedValue(
        createMockAuthSession(mockUser)
      );
      mockPrisma.featureRequest.findUnique.mockResolvedValue(
        mockFeatureRequest
      );

      const updatedRequest = {
        ...mockFeatureRequest,
        title: "Updated Title",
        description: "Updated Description",
      };
      mockPrisma.featureRequest.update.mockResolvedValue(updatedRequest);
      mockPrisma.activity.create.mockResolvedValue({});

      const req = createMockRequest({
        method: "PUT",
        body: { title: "Updated Title", description: "Updated Description" },
      });
      const response = await PUT(
        req as any,
        { params: { id: "fr-123" } } as any
      );

      // Assertions
      expect(response.status).toBe(200);
      expect(mockPrisma.featureRequest.update).toHaveBeenCalledWith({
        where: { id: "fr-123" },
        data: { title: "Updated Title", description: "Updated Description" },
        include: expect.any(Object),
      });
      expect(mockPrisma.activity.create).toHaveBeenCalledWith({
        data: {
          type: "edited",
          userId: mockUser.id,
          featureRequestId: "fr-123",
        },
      });
    });

    it("should handle database errors", async () => {
      // Setup
      (getServerSession as jest.Mock).mockResolvedValue(
        createMockAuthSession(mockUser)
      );
      mockPrisma.featureRequest.findUnique.mockResolvedValue(
        mockFeatureRequest
      );
      mockPrisma.featureRequest.update.mockRejectedValue(
        new Error("Database error")
      );

      const req = createMockRequest({
        method: "PUT",
        body: { title: "Updated Title", description: "Updated Description" },
      });
      const response = await PUT(
        req as any,
        { params: { id: "fr-123" } } as any
      );

      // Assertions
      expect(response.status).toBe(500);
      expect(response.data.message).toBe("Failed to edit feature request");
    });
  });

  describe("DELETE handler", () => {
    it("should return 401 if user is not authenticated", async () => {
      // Setup
      (getServerSession as jest.Mock).mockResolvedValue(
        createMockUnauthSession()
      );

      const req = createMockRequest({ method: "DELETE" });
      const response = await DELETE(
        req as any,
        { params: { id: "fr-123" } } as any
      );

      // Assertions
      expect(response.status).toBe(401);
      expect(response.data.message).toBe("Unauthorized");
      expect(mockPrisma.featureRequest.findUnique).not.toHaveBeenCalled();
    });

    it("should return 404 if feature request doesn't exist", async () => {
      // Setup
      (getServerSession as jest.Mock).mockResolvedValue(
        createMockAuthSession(mockUser)
      );
      mockPrisma.featureRequest.findUnique.mockResolvedValue(null);

      const req = createMockRequest({ method: "DELETE" });
      const response = await DELETE(
        req as any,
        { params: { id: "non-existent-id" } } as any
      );

      // Assertions
      expect(response.status).toBe(404);
      expect(response.data.message).toBe("Feature request not found");
      expect(mockPrisma.$transaction).not.toHaveBeenCalled();
    });

    it("should return 403 if user is not the owner", async () => {
      // Setup
      (getServerSession as jest.Mock).mockResolvedValue(
        createMockAuthSession(mockUser)
      );
      mockPrisma.featureRequest.findUnique.mockResolvedValue(
        mockRequestFromAnotherUser
      );

      const req = createMockRequest({ method: "DELETE" });
      const response = await DELETE(
        req as any,
        { params: { id: "fr-789" } } as any
      );

      // Assertions
      expect(response.status).toBe(403);
      expect(response.data.message).toBe(
        "You can only delete your own requests"
      );
      expect(mockPrisma.$transaction).not.toHaveBeenCalled();
    });

    it("should return 403 if feature request has votes", async () => {
      // Setup
      (getServerSession as jest.Mock).mockResolvedValue(
        createMockAuthSession(mockUser)
      );
      mockPrisma.featureRequest.findUnique.mockResolvedValue(
        mockRequestWithVotes
      );

      const req = createMockRequest({ method: "DELETE" });
      const response = await DELETE(
        req as any,
        { params: { id: "fr-456" } } as any
      );

      // Assertions
      expect(response.status).toBe(403);
      expect(response.data.message).toBe(
        "Cannot delete a request that has votes"
      );
      expect(mockPrisma.$transaction).not.toHaveBeenCalled();
    });

    it("should delete the feature request successfully", async () => {
      // Setup
      (getServerSession as jest.Mock).mockResolvedValue(
        createMockAuthSession(mockUser)
      );
      mockPrisma.featureRequest.findUnique.mockResolvedValue(
        mockFeatureRequest
      );

      // Mock transaction
      mockPrisma.$transaction.mockImplementation(async (callback) => {
        if (typeof callback === "function") {
          await callback(mockPrisma);
        }
        return null;
      });

      mockPrisma.activity.create.mockResolvedValue({});
      mockPrisma.activity.deleteMany.mockResolvedValue({ count: 0 });
      mockPrisma.featureRequest.delete.mockResolvedValue(mockFeatureRequest);

      const req = createMockRequest({ method: "DELETE" });
      const response = await DELETE(
        req as any,
        { params: { id: "fr-123" } } as any
      );

      // Assertions
      expect(response.status).toBe(200);
      expect(response.data.message).toBe(
        "Feature request deleted successfully"
      );
      expect(mockPrisma.activity.create).toHaveBeenCalledWith({
        data: {
          type: "deleted",
          userId: mockUser.id,
          deletedRequestTitle: mockFeatureRequest.title,
        },
      });
      expect(mockPrisma.$transaction).toHaveBeenCalled();
    });

    it("should handle database errors", async () => {
      // Setup
      (getServerSession as jest.Mock).mockResolvedValue(
        createMockAuthSession(mockUser)
      );
      mockPrisma.featureRequest.findUnique.mockResolvedValue(
        mockFeatureRequest
      );
      mockPrisma.activity.create.mockRejectedValue(new Error("Database error"));

      const req = createMockRequest({ method: "DELETE" });
      const response = await DELETE(
        req as any,
        { params: { id: "fr-123" } } as any
      );

      // Assertions
      expect(response.status).toBe(500);
      expect(response.data.message).toBe("Failed to delete feature request");
    });
  });
});
