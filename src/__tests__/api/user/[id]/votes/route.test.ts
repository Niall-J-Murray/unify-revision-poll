import { NextResponse } from "next/server";
import { mockPrisma } from "../../../../helpers/prisma-mock";
import { createMockRequest } from "../../../../helpers/api-test-helpers";

// Mock dependencies
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

// Mock console.error to suppress output during tests
jest.spyOn(console, "error").mockImplementation(() => {});

// Import the route handler after mocking dependencies
import { GET } from "@/app/api/user/[id]/votes/route";

describe("User Votes API", () => {
  const userId = "user-123";

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("should return the correct vote count", async () => {
    // Setup
    mockPrisma.vote.count.mockResolvedValue(10);

    const req = createMockRequest({
      method: "GET",
    });
    const response = await GET(req as any, { params: { id: userId } } as any);

    // Assertions
    expect(response.status).toBe(200);
    expect(response.data).toEqual({ count: 10 });
    expect(mockPrisma.vote.count).toHaveBeenCalledWith({
      where: { userId },
    });
  });

  it("should return zero when user has no votes", async () => {
    // Setup
    mockPrisma.vote.count.mockResolvedValue(0);

    const req = createMockRequest({
      method: "GET",
    });
    const response = await GET(req as any, { params: { id: userId } } as any);

    // Assertions
    expect(response.status).toBe(200);
    expect(response.data).toEqual({ count: 0 });
    expect(mockPrisma.vote.count).toHaveBeenCalledWith({
      where: { userId },
    });
  });

  it("should handle database errors", async () => {
    // Setup
    mockPrisma.vote.count.mockRejectedValue(new Error("Database error"));

    const req = createMockRequest({
      method: "GET",
    });
    const response = await GET(req as any, { params: { id: userId } } as any);

    // Assertions
    expect(response.status).toBe(500);
    expect(response.data.message).toBe("Failed to fetch votes");
  });

  it("should handle invalid user ID format", async () => {
    // Test with invalid ID format
    const req = createMockRequest({
      method: "GET",
    });

    // Test with empty ID
    const response = await GET(req as any, { params: { id: "" } } as any);

    // Assertions
    expect(response.status).toBe(500);
    expect(response.data.message).toBe("Failed to fetch votes");
    expect(mockPrisma.vote.count).toHaveBeenCalledWith({
      where: { userId: "" },
    });
  });
});
