import { createMockNextRequest } from "../../../../helpers/next-request-helpers";
import { prismaMock } from "../../../../helpers/prisma-mock";
import { mockPrisma } from "../../../../helpers/prisma-mock";
import {
  createMockRequest,
  mockAuthenticatedSession,
  mockUnauthenticatedSession,
} from "../../../../helpers/api-test-helpers";

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

// Import the actual route handler
import { POST } from "@/app/api/feature-requests/[id]/vote/route";

describe("Feature Request Vote API", () => {
  // Reset all mocks before each test
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("should return 401 if user is not authenticated", async () => {
    // Mock unauthenticated session
    require("next-auth/next").getServerSession.mockResolvedValueOnce(null);

    const req = createMockRequest({
      method: "POST",
    });

    const response = await POST(req, { params: { id: "fr-1" } });
    expect(response.status).toBe(401);

    const data = await response.json();
    expect(data.success).toBe(false);
    expect(data.message).toBe("Unauthorized");
  });

  it("should return 404 if feature request does not exist", async () => {
    // Mock feature request not found
    mockPrisma.featureRequest.findUnique.mockResolvedValueOnce(null);

    const req = createMockRequest({
      method: "POST",
    });

    const response = await POST(req, { params: { id: "fr-1" } });
    expect(response.status).toBe(404);

    const data = await response.json();
    expect(data.success).toBe(false);
    expect(data.message).toBe("Feature request not found");
  });

  it("should return 403 if user tries to vote on their own request", async () => {
    // Mock feature request owned by the user
    mockPrisma.featureRequest.findUnique.mockResolvedValueOnce({
      id: "fr-1",
      title: "Feature 1",
      description: "Description 1",
      status: "OPEN",
      createdAt: new Date(),
      updatedAt: new Date(),
      userId: "user-1", // Same as the authenticated user
    });

    const req = createMockRequest({
      method: "POST",
    });

    const response = await POST(req, { params: { id: "fr-1" } });
    expect(response.status).toBe(403);

    const data = await response.json();
    expect(data.success).toBe(false);
    expect(data.message).toBe("You cannot vote on your own request");
  });

  it("should remove an existing vote", async () => {
    // Mock feature request
    mockPrisma.featureRequest.findUnique.mockResolvedValueOnce({
      id: "fr-1",
      title: "Feature 1",
      description: "Description 1",
      status: "OPEN",
      createdAt: new Date(),
      updatedAt: new Date(),
      userId: "user-2", // Different from the authenticated user
    });

    // Mock existing vote
    mockPrisma.vote.findUnique.mockResolvedValueOnce({
      id: "vote-1",
      userId: "user-1",
      featureRequestId: "fr-1",
      createdAt: new Date(),
    });

    // Mock vote deletion
    mockPrisma.vote.delete.mockResolvedValueOnce({
      id: "vote-1",
      userId: "user-1",
      featureRequestId: "fr-1",
      createdAt: new Date(),
    });

    // Mock activity creation
    mockPrisma.activity.create.mockResolvedValueOnce({
      id: "activity-1",
      type: "unvoted",
      userId: "user-1",
      featureRequestId: "fr-1",
      createdAt: new Date(),
    });

    const req = createMockRequest({
      method: "POST",
    });

    const response = await POST(req, { params: { id: "fr-1" } });
    expect(response.status).toBe(200);

    const data = await response.json();
    expect(data.success).toBe(true);
    expect(data.message).toBe("Vote removed");
    expect(data.action).toBe("removed");

    // Verify vote was deleted
    expect(mockPrisma.vote.delete).toHaveBeenCalledWith({
      where: { id: "vote-1" },
    });

    // Verify activity was created
    expect(mockPrisma.activity.create).toHaveBeenCalledWith({
      data: {
        type: "unvoted",
        userId: "user-1",
        featureRequestId: "fr-1",
      },
    });
  });

  it("should add a new vote", async () => {
    // Mock feature request
    mockPrisma.featureRequest.findUnique.mockResolvedValueOnce({
      id: "fr-1",
      title: "Feature 1",
      description: "Description 1",
      status: "OPEN",
      createdAt: new Date(),
      updatedAt: new Date(),
      userId: "user-2", // Different from the authenticated user
    });

    // Mock no existing vote
    mockPrisma.vote.findUnique.mockResolvedValueOnce(null);

    // Mock vote creation
    mockPrisma.vote.create.mockResolvedValueOnce({
      id: "vote-1",
      userId: "user-1",
      featureRequestId: "fr-1",
      createdAt: new Date(),
    });

    // Mock activity creation
    mockPrisma.activity.create.mockResolvedValueOnce({
      id: "activity-1",
      type: "voted",
      userId: "user-1",
      featureRequestId: "fr-1",
      createdAt: new Date(),
    });

    const req = createMockRequest({
      method: "POST",
    });

    const response = await POST(req, { params: { id: "fr-1" } });
    expect(response.status).toBe(200);

    const data = await response.json();
    expect(data.success).toBe(true);
    expect(data.message).toBe("Vote added");
    expect(data.action).toBe("added");

    // Verify vote was created
    expect(mockPrisma.vote.create).toHaveBeenCalledWith({
      data: {
        userId: "user-1",
        featureRequestId: "fr-1",
      },
    });

    // Verify activity was created
    expect(mockPrisma.activity.create).toHaveBeenCalledWith({
      data: {
        type: "voted",
        userId: "user-1",
        featureRequestId: "fr-1",
      },
    });
  });

  it("should handle database errors gracefully", async () => {
    // Mock database error
    mockPrisma.featureRequest.findUnique.mockRejectedValueOnce(
      new Error("Database error")
    );

    const req = createMockRequest({
      method: "POST",
    });

    const response = await POST(req, { params: { id: "fr-1" } });
    expect(response.status).toBe(500);

    const data = await response.json();
    expect(data.success).toBe(false);
    expect(data.message).toBe("Failed to process vote");
  });
});
