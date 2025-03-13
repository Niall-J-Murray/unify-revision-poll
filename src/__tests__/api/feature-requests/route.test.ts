import { createMockNextRequest } from "../../helpers/next-request-helpers";
import { prismaMock } from "../../helpers/prisma-mock";
import { mockPrisma } from "../../helpers/prisma-mock";
import {
  createMockRequest,
  mockAuthenticatedSession,
  mockUnauthenticatedSession,
} from "../../helpers/api-test-helpers";

// Mock dependencies
jest.mock("@/lib/prisma", () => ({
  prisma: mockPrisma,
}));

const mockSession = {
  user: { id: "user-1", name: "Test User", email: "test@example.com" },
};

jest.mock("next-auth/next", () => ({
  getServerSession: jest.fn(() => Promise.resolve(mockSession)),
}));

jest.mock("@/app/api/auth/[...nextauth]/route", () => ({
  authOptions: {
    providers: [],
    callbacks: {},
  },
}));

// Import the actual route handlers
import { GET, POST } from "@/app/api/feature-requests/route";

describe("Feature Requests API", () => {
  // Reset all mocks before each test
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("GET /api/feature-requests", () => {
    it("should return all feature requests with proper filtering and sorting", async () => {
      // Mock feature requests
      const mockFeatureRequests = [
        {
          id: "fr-1",
          title: "Feature 1",
          description: "Description 1",
          status: "OPEN",
          createdAt: new Date(),
          updatedAt: new Date(),
          userId: "user-1",
          user: {
            name: "User 1",
            email: "user1@example.com",
          },
          votes: [{ userId: "voter-1" }, { userId: "voter-2" }],
        },
        {
          id: "fr-2",
          title: "Feature 2",
          description: "Description 2",
          status: "IN_PROGRESS",
          createdAt: new Date(),
          updatedAt: new Date(),
          userId: "user-2",
          user: {
            name: "User 2",
            email: "user2@example.com",
          },
          votes: [{ userId: "voter-1" }],
        },
      ];

      // Mock Prisma response
      mockPrisma.featureRequest.findMany.mockResolvedValueOnce(
        mockFeatureRequests
      );

      // Create request with search params
      const req = createMockRequest({
        method: "GET",
        searchParams: { status: "OPEN", sort: "votes" },
      });

      const response = await GET(req);
      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data.success).toBe(true);
      expect(data.featureRequests).toHaveLength(2);
      expect(data.featureRequests[0].voteCount).toBe(2);
      expect(data.featureRequests[1].voteCount).toBe(1);

      // Verify Prisma was called with correct parameters
      expect(mockPrisma.featureRequest.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({
            status: { notIn: ["COMPLETED", "IN_PROGRESS", "REJECTED"] },
          }),
          include: expect.objectContaining({
            user: expect.any(Object),
            votes: expect.any(Object),
          }),
          orderBy: { votes: { _count: "desc" } },
        })
      );
    });

    it("should handle view filters for authenticated users", async () => {
      // Mock authenticated session
      const mockSession = {
        user: { id: "user-1", name: "Test User", email: "test@example.com" },
      };
      require("next-auth/next").getServerSession.mockResolvedValueOnce(
        mockSession
      );

      // Mock feature requests
      mockPrisma.featureRequest.findMany.mockResolvedValueOnce([]);

      // Create request with view filter
      const req = createMockRequest({
        method: "GET",
        searchParams: { view: "MINE" },
      });

      await GET(req);

      // Verify Prisma was called with user filter
      expect(mockPrisma.featureRequest.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({
            userId: "user-1",
          }),
        })
      );
    });

    it("should handle database errors gracefully", async () => {
      // Mock database error
      mockPrisma.featureRequest.findMany.mockRejectedValueOnce(
        new Error("Database error")
      );

      const req = createMockRequest({
        method: "GET",
      });

      const response = await GET(req);
      expect(response.status).toBe(500);

      const data = await response.json();
      expect(data.success).toBe(false);
      expect(data.message).toContain("Failed to fetch feature requests");
    });

    it("should handle ALL status filter", async () => {
      // Mock feature requests
      mockPrisma.featureRequest.findMany.mockResolvedValueOnce([]);

      // Create request with ALL status
      const req = createMockRequest({
        method: "GET",
        searchParams: { status: "ALL" },
      });

      await GET(req);

      // Verify Prisma was called without status filter
      expect(mockPrisma.featureRequest.findMany).toHaveBeenCalledWith(
        expect.not.objectContaining({
          status: expect.anything(),
        })
      );
    });

    it("should handle non-OPEN status filter", async () => {
      // Mock feature requests
      mockPrisma.featureRequest.findMany.mockResolvedValueOnce([]);

      // Create request with IN_PROGRESS status
      const req = createMockRequest({
        method: "GET",
        searchParams: { status: "IN_PROGRESS" },
      });

      await GET(req);

      // Verify Prisma was called with exact status filter
      expect(mockPrisma.featureRequest.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({
            status: "IN_PROGRESS",
          }),
        })
      );
    });

    it("should handle ALL view filter", async () => {
      // Mock feature requests
      mockPrisma.featureRequest.findMany.mockResolvedValueOnce([]);

      // Create request with ALL view
      const req = createMockRequest({
        method: "GET",
        searchParams: { view: "ALL" },
      });

      await GET(req);

      // Verify Prisma was called without user filters
      expect(mockPrisma.featureRequest.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.not.objectContaining({
            userId: expect.anything(),
            votes: expect.anything(),
          }),
        })
      );
    });

    it("should handle VOTED view filter", async () => {
      // Mock feature requests
      mockPrisma.featureRequest.findMany.mockResolvedValueOnce([]);

      // Create request with VOTED view
      const req = createMockRequest({
        method: "GET",
        searchParams: { view: "VOTED" },
      });

      await GET(req);

      // Verify Prisma was called with votes filter
      expect(mockPrisma.featureRequest.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({
            votes: {
              some: {
                userId: "user-1",
              },
            },
          }),
        })
      );
    });

    it("should handle different sorting options", async () => {
      // Mock feature requests with votes
      const mockFeatureRequests = [
        {
          id: "fr-1",
          title: "Feature 1",
          description: "Description 1",
          status: "OPEN",
          createdAt: new Date(),
          updatedAt: new Date(),
          userId: "user-1",
          user: {
            name: "User 1",
            email: "user1@example.com",
          },
          votes: [{ userId: "voter-1" }],
        },
      ];

      // Test newest sort
      mockPrisma.featureRequest.findMany.mockResolvedValueOnce(
        mockFeatureRequests
      );

      const reqNewest = createMockRequest({
        method: "GET",
        searchParams: { sort: "newest" },
      });

      await GET(reqNewest);

      // Verify Prisma was called with newest sort
      expect(mockPrisma.featureRequest.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          orderBy: { createdAt: "desc" },
        })
      );

      // Test oldest sort
      mockPrisma.featureRequest.findMany.mockResolvedValueOnce(
        mockFeatureRequests
      );

      const reqOldest = createMockRequest({
        method: "GET",
        searchParams: { sort: "oldest" },
      });

      await GET(reqOldest);

      // Verify Prisma was called with oldest sort
      expect(mockPrisma.featureRequest.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          orderBy: { createdAt: "asc" },
        })
      );

      // Test default (votes) sort
      mockPrisma.featureRequest.findMany.mockResolvedValueOnce(
        mockFeatureRequests
      );

      const reqDefault = createMockRequest({
        method: "GET",
        searchParams: {},
      });

      await GET(reqDefault);

      // Verify Prisma was called with votes sort
      expect(mockPrisma.featureRequest.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          orderBy: { votes: { _count: "desc" } },
        })
      );
    });
  });

  describe("POST /api/feature-requests", () => {
    it("should return 401 if user is not authenticated", async () => {
      // Mock unauthenticated session
      require("next-auth/next").getServerSession.mockResolvedValueOnce(null);

      const req = createMockRequest({
        method: "POST",
        body: {
          title: "New Feature",
          description: "Feature description",
        },
      });

      const response = await POST(req);
      expect(response.status).toBe(401);

      const data = await response.json();
      expect(data.message).toBe("Unauthorized");
    });

    it("should validate input fields", async () => {
      // Test missing title
      const reqWithoutTitle = createMockRequest({
        method: "POST",
        body: {
          description: "Feature description",
        },
      });

      const responseWithoutTitle = await POST(reqWithoutTitle);
      expect(responseWithoutTitle.status).toBe(400);

      const dataWithoutTitle = await responseWithoutTitle.json();
      expect(dataWithoutTitle.success).toBe(false);
      expect(dataWithoutTitle.message).toBe(
        "Title and description are required"
      );

      // Test title too long
      const reqWithLongTitle = createMockRequest({
        method: "POST",
        body: {
          title: "x".repeat(101),
          description: "Feature description",
        },
      });

      const responseWithLongTitle = await POST(reqWithLongTitle);
      expect(responseWithLongTitle.status).toBe(400);

      const dataWithLongTitle = await responseWithLongTitle.json();
      expect(dataWithLongTitle.success).toBe(false);
      expect(dataWithLongTitle.message).toBe(
        "Title must be 100 characters or less"
      );
    });

    it("should validate description length", async () => {
      const reqWithLongDescription = createMockRequest({
        method: "POST",
        body: {
          title: "New Feature",
          description: "x".repeat(501),
        },
      });

      const responseWithLongDescription = await POST(reqWithLongDescription);
      expect(responseWithLongDescription.status).toBe(400);

      const dataWithLongDescription = await responseWithLongDescription.json();
      expect(dataWithLongDescription.success).toBe(false);
      expect(dataWithLongDescription.message).toBe(
        "Description must be 500 characters or less"
      );
    });

    it("should create a new feature request successfully", async () => {
      const mockDate = new Date("2025-03-12T20:49:29.138Z");
      const mockFeatureRequest = {
        id: "new-fr",
        title: "New Feature",
        description: "Feature description",
        status: "OPEN",
        createdAt: mockDate.toISOString(),
        updatedAt: mockDate.toISOString(),
        userId: "user-1",
      };

      // Mock creating a new feature request
      mockPrisma.featureRequest.create.mockResolvedValueOnce({
        ...mockFeatureRequest,
        createdAt: mockDate,
        updatedAt: mockDate,
      });

      mockPrisma.activity.create.mockResolvedValueOnce({
        id: "activity-1",
        type: "created",
        userId: "user-1",
        featureRequestId: "new-fr",
        createdAt: mockDate,
      });

      const req = createMockRequest({
        method: "POST",
        body: {
          title: "New Feature",
          description: "Feature description",
        },
      });

      const response = await POST(req);
      expect(response.status).toBe(200);

      const data = await response.json();
      expect(data).toEqual(mockFeatureRequest);

      // Verify activity was created
      expect(mockPrisma.activity.create).toHaveBeenCalledWith({
        data: {
          type: "created",
          userId: "user-1",
          featureRequestId: "new-fr",
        },
      });
    });

    it("should handle database errors gracefully", async () => {
      // Mock authenticated session
      const mockSession = {
        user: { id: "user-1", name: "Test User", email: "test@example.com" },
      };
      require("next-auth/next").getServerSession.mockResolvedValueOnce(
        mockSession
      );

      // Mock database error
      mockPrisma.featureRequest.create.mockRejectedValueOnce(
        new Error("Database error")
      );

      const req = createMockRequest({
        method: "POST",
        body: {
          title: "New Feature",
          description: "Feature description",
        },
      });

      const response = await POST(req);
      expect(response.status).toBe(500);

      const data = await response.json();
      expect(data.message).toBe("Failed to create feature request");
    });
  });
});
