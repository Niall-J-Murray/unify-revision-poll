import { NextResponse } from "next/server";
import { mockPrisma } from "../../../../helpers/prisma-mock";
import { createMockRequest } from "../../../../helpers/api-test-helpers";
import {
  createMockAuthSession,
  createMockUnauthSession,
} from "../../../../helpers/auth-helpers";

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

// Import the route handler after mocking dependencies
import { GET } from "@/app/api/user/[id]/activity/route";
import { getServerSession } from "next-auth/next";

describe("User Activity API", () => {
  const mockUser = {
    id: "user-123",
    name: "Test User",
    email: "test@example.com",
    role: "user",
  };

  const mockActivities = [
    {
      id: "activity-1",
      type: "created",
      userId: "user-123",
      featureRequestId: "fr-1",
      deletedRequestTitle: null,
      createdAt: new Date("2023-01-01"),
      featureRequest: {
        title: "Feature Request 1",
      },
    },
    {
      id: "activity-2",
      type: "deleted",
      userId: "user-123",
      featureRequestId: null,
      deletedRequestTitle: "Deleted Feature Request",
      createdAt: new Date("2023-01-02"),
      featureRequest: null,
    },
    {
      id: "activity-3",
      type: "voted",
      userId: "user-123",
      featureRequestId: "fr-2",
      deletedRequestTitle: null,
      createdAt: new Date("2023-01-03"),
      featureRequest: {
        title: "Feature Request 2",
      },
    },
  ];

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("should return 401 if user is not authenticated", async () => {
    // Setup
    (getServerSession as jest.Mock).mockResolvedValue(
      createMockUnauthSession()
    );

    const req = createMockRequest({
      method: "GET",
      url: "https://example.com/api/user/user-123/activity",
    });
    const response = await GET(
      req as any,
      { params: { id: "user-123" } } as any
    );

    // Assertions
    expect(response.status).toBe(401);
    expect(response.data.message).toBe("Unauthorized");
    expect(mockPrisma.activity.findMany).not.toHaveBeenCalled();
  });

  it("should return 403 if user tries to view another user's activity", async () => {
    // Setup
    (getServerSession as jest.Mock).mockResolvedValue(
      createMockAuthSession(mockUser)
    );

    const req = createMockRequest({
      method: "GET",
      url: "https://example.com/api/user/another-user-456/activity",
    });
    const response = await GET(
      req as any,
      { params: { id: "another-user-456" } } as any
    );

    // Assertions
    expect(response.status).toBe(403);
    expect(response.data.message).toBe("You can only view your own activity");
    expect(mockPrisma.activity.findMany).not.toHaveBeenCalled();
  });

  it("should return user's activities successfully", async () => {
    // Setup
    (getServerSession as jest.Mock).mockResolvedValue(
      createMockAuthSession(mockUser)
    );
    mockPrisma.activity.findMany.mockResolvedValue(mockActivities);

    const req = createMockRequest({
      method: "GET",
      url: `https://example.com/api/user/${mockUser.id}/activity`,
    });
    const response = await GET(
      req as any,
      { params: { id: mockUser.id } } as any
    );

    // Assertions
    expect(response.status).toBe(200);
    expect(mockPrisma.activity.findMany).toHaveBeenCalledWith({
      where: {
        userId: mockUser.id,
      },
      include: expect.any(Object),
      orderBy: {
        createdAt: "desc",
      },
      take: 10, // Should limit to last 10 activities
    });

    // Check mapping for deleted activities
    expect(response.data).toHaveLength(3);
    expect(response.data[1].featureRequest).toEqual({
      title: "Deleted Feature Request",
    });
  });

  it("should handle empty activities", async () => {
    // Setup
    (getServerSession as jest.Mock).mockResolvedValue(
      createMockAuthSession(mockUser)
    );
    mockPrisma.activity.findMany.mockResolvedValue([]);

    const req = createMockRequest({
      method: "GET",
      url: `https://example.com/api/user/${mockUser.id}/activity`,
    });
    const response = await GET(
      req as any,
      { params: { id: mockUser.id } } as any
    );

    // Assertions
    expect(response.status).toBe(200);
    expect(response.data).toEqual([]);
  });

  it("should handle database errors", async () => {
    // Setup
    (getServerSession as jest.Mock).mockResolvedValue(
      createMockAuthSession(mockUser)
    );
    mockPrisma.activity.findMany.mockRejectedValue(new Error("Database error"));

    const req = createMockRequest({
      method: "GET",
      url: `https://example.com/api/user/${mockUser.id}/activity`,
    });
    const response = await GET(
      req as any,
      { params: { id: mockUser.id } } as any
    );

    // Assertions
    expect(response.status).toBe(500);
    expect(response.data.message).toBe("Failed to fetch activity");
  });
});
