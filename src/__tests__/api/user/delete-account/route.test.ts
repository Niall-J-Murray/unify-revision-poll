import { NextResponse } from "next/server";
import { mockPrisma } from "../../../helpers/prisma-mock";
import { createMockRequest } from "../../../helpers/api-test-helpers";
import {
  createMockAuthSession,
  createMockUnauthSession,
} from "../../../helpers/auth-helpers";
import bcrypt from "bcryptjs";

// Mock dependencies
jest.mock("@/lib/prisma", () => ({
  prisma: mockPrisma,
}));

jest.mock("bcryptjs", () => ({
  compare: jest.fn(),
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
import { POST } from "@/app/api/user/delete-account/route";
import { getServerSession } from "next-auth/next";

describe("Delete Account API", () => {
  const mockUser = {
    id: "user-123",
    name: "Test User",
    email: "test@example.com",
    role: "user",
  };

  const mockUserWithPassword = {
    id: "user-123",
    email: "test@example.com",
    password: "hashed-password",
  };

  const mockSystemUser = {
    id: "system-user",
    email: "system@unify-poll.com",
    name: "System (Deleted User Content)",
    role: "SYSTEM",
  };

  const mockFeatureRequests = [
    {
      id: "fr-1",
      userId: "user-123",
      title: "Feature with few votes",
      description: "Description 1",
      _count: { votes: 1 },
    },
    {
      id: "fr-2",
      userId: "user-123",
      title: "Popular feature",
      description: "Description 2",
      _count: { votes: 5 },
    },
  ];

  const mockVotes = [
    {
      id: "vote-1",
      userId: "user-123",
      featureRequestId: "other-fr-1",
      featureRequest: { _count: { votes: 2 } },
    },
    {
      id: "vote-2",
      userId: "user-123",
      featureRequestId: "other-fr-2",
      featureRequest: { _count: { votes: 4 } },
    },
  ];

  beforeEach(() => {
    jest.clearAllMocks();

    // Setup transaction mock to execute the callback
    mockPrisma.$transaction.mockImplementation(async (callback) => {
      if (typeof callback === "function") {
        await callback(mockPrisma);
      }
      return null;
    });
  });

  it("should return 401 if user is not authenticated", async () => {
    // Setup
    (getServerSession as jest.Mock).mockResolvedValue(
      createMockUnauthSession()
    );

    const req = createMockRequest({
      method: "POST",
      body: { password: "correct-password" },
    });
    const response = await POST(req as any);

    // Assertions
    expect(response.status).toBe(401);
    expect(response.data.success).toBe(false);
    expect(response.data.message).toBe("Unauthorized");
    expect(mockPrisma.user.findUnique).not.toHaveBeenCalled();
  });

  it("should return 400 if password is not provided", async () => {
    // Setup
    (getServerSession as jest.Mock).mockResolvedValue(
      createMockAuthSession(mockUser)
    );

    const req = createMockRequest({
      method: "POST",
      body: {},
    });
    const response = await POST(req as any);

    // Assertions
    expect(response.status).toBe(400);
    expect(response.data.success).toBe(false);
    expect(response.data.message).toBe("Password is required");
    expect(mockPrisma.user.findUnique).not.toHaveBeenCalled();
  });

  it("should return 404 if user is not found", async () => {
    // Setup
    (getServerSession as jest.Mock).mockResolvedValue(
      createMockAuthSession(mockUser)
    );
    mockPrisma.user.findUnique.mockResolvedValue(null);

    const req = createMockRequest({
      method: "POST",
      body: { password: "correct-password" },
    });
    const response = await POST(req as any);

    // Assertions
    expect(response.status).toBe(404);
    expect(response.data.success).toBe(false);
    expect(response.data.message).toBe("User not found or no password set");
    expect(mockPrisma.$transaction).not.toHaveBeenCalled();
  });

  it("should return 400 if password is incorrect", async () => {
    // Setup
    (getServerSession as jest.Mock).mockResolvedValue(
      createMockAuthSession(mockUser)
    );
    mockPrisma.user.findUnique.mockResolvedValue(mockUserWithPassword);
    (bcrypt.compare as jest.Mock).mockResolvedValue(false);

    const req = createMockRequest({
      method: "POST",
      body: { password: "wrong-password" },
    });
    const response = await POST(req as any);

    // Assertions
    expect(response.status).toBe(400);
    expect(response.data.success).toBe(false);
    expect(response.data.message).toBe("Password is incorrect");
    expect(mockPrisma.$transaction).not.toHaveBeenCalled();
  });

  it("should successfully delete account and manage related data", async () => {
    // Setup
    (getServerSession as jest.Mock).mockResolvedValue(
      createMockAuthSession(mockUser)
    );
    mockPrisma.user.findUnique.mockResolvedValueOnce(mockUserWithPassword);
    (bcrypt.compare as jest.Mock).mockResolvedValue(true);

    // Mock system user creation flow
    mockPrisma.user.findUnique.mockResolvedValueOnce(mockSystemUser); // For system user check

    // Setup feature requests and votes
    mockPrisma.featureRequest.findMany.mockResolvedValue(mockFeatureRequests);
    mockPrisma.vote.findMany.mockResolvedValue(mockVotes);

    mockPrisma.featureRequest.deleteMany.mockResolvedValue({ count: 1 });
    mockPrisma.featureRequest.updateMany.mockResolvedValue({ count: 1 });
    mockPrisma.vote.deleteMany.mockResolvedValue({ count: 1 });
    mockPrisma.vote.updateMany.mockResolvedValue({ count: 1 });
    mockPrisma.activity.deleteMany.mockResolvedValue({ count: 5 });
    mockPrisma.user.delete.mockResolvedValue(mockUser);

    const req = createMockRequest({
      method: "POST",
      body: { password: "correct-password" },
    });
    const response = await POST(req as any);

    // Assertions
    expect(response.status).toBe(200);
    expect(response.data.success).toBe(true);
    expect(response.data.message).toBe("Account deleted successfully");

    // Verify transaction was used
    expect(mockPrisma.$transaction).toHaveBeenCalled();

    // Check feature request operations
    expect(mockPrisma.featureRequest.findMany).toHaveBeenCalledWith({
      where: { userId: mockUser.id },
      include: expect.any(Object),
    });

    // Verify popular feature requests were transferred
    expect(mockPrisma.featureRequest.updateMany).toHaveBeenCalledWith({
      where: { id: { in: ["fr-2"] } },
      data: expect.objectContaining({
        userId: "system-user",
      }),
    });

    // Verify low-vote feature requests were deleted
    expect(mockPrisma.featureRequest.deleteMany).toHaveBeenCalledWith({
      where: { id: { in: ["fr-1"] } },
    });

    // Check vote operations were performed
    expect(mockPrisma.vote.findMany).toHaveBeenCalledWith({
      where: { userId: mockUser.id },
      include: expect.any(Object),
    });

    // Verify votes on popular features were transferred
    expect(mockPrisma.vote.updateMany).toHaveBeenCalledWith({
      where: { id: { in: ["vote-2"] } },
      data: { userId: "system-user" },
    });

    // Verify low-count votes were deleted
    expect(mockPrisma.vote.deleteMany).toHaveBeenCalledWith({
      where: { id: { in: ["vote-1"] } },
    });

    // Verify activities were deleted
    expect(mockPrisma.activity.deleteMany).toHaveBeenCalledWith({
      where: { userId: mockUser.id },
    });

    // Verify user was deleted
    expect(mockPrisma.user.delete).toHaveBeenCalledWith({
      where: { id: mockUser.id },
    });
  });

  it("should create system user if it doesn't exist", async () => {
    // Setup
    (getServerSession as jest.Mock).mockResolvedValue(
      createMockAuthSession(mockUser)
    );
    mockPrisma.user.findUnique.mockResolvedValueOnce(mockUserWithPassword);
    (bcrypt.compare as jest.Mock).mockResolvedValue(true);

    // System user doesn't exist yet
    mockPrisma.user.findUnique.mockResolvedValueOnce(null);
    mockPrisma.user.create.mockResolvedValue(mockSystemUser);

    // Setup empty feature requests and votes
    mockPrisma.featureRequest.findMany.mockResolvedValue([]);
    mockPrisma.vote.findMany.mockResolvedValue([]);
    mockPrisma.activity.deleteMany.mockResolvedValue({ count: 0 });
    mockPrisma.user.delete.mockResolvedValue(mockUser);

    const req = createMockRequest({
      method: "POST",
      body: { password: "correct-password" },
    });
    const response = await POST(req as any);

    // Assertions
    expect(response.status).toBe(200);
    expect(response.data.success).toBe(true);

    // Verify system user was created
    expect(mockPrisma.user.create).toHaveBeenCalledWith({
      data: {
        email: "system@unify-poll.com",
        name: "System (Deleted User Content)",
        role: "SYSTEM",
      },
    });
  });

  it("should handle database errors", async () => {
    // Setup
    (getServerSession as jest.Mock).mockResolvedValue(
      createMockAuthSession(mockUser)
    );
    mockPrisma.user.findUnique.mockResolvedValue(mockUserWithPassword);
    (bcrypt.compare as jest.Mock).mockResolvedValue(true);

    // Simulate a transaction error
    mockPrisma.$transaction.mockRejectedValue(new Error("Database error"));

    const req = createMockRequest({
      method: "POST",
      body: { password: "correct-password" },
    });
    const response = await POST(req as any);

    // Assertions
    expect(response.status).toBe(500);
    expect(response.data.success).toBe(false);
    expect(response.data.message).toBe("Failed to delete account");
  });
});
