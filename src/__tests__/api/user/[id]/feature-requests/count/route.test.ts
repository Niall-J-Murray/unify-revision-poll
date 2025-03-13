import { NextResponse } from "next/server";
import { mockPrisma } from "../../../../../helpers/prisma-mock";
import { createMockRequest } from "../../../../../helpers/api-test-helpers";

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

// Import the route handler after mocking dependencies
import { GET } from "@/app/api/user/[id]/feature-requests/count/route";

describe("User Feature Requests Count API", () => {
  const userId = "user-123";

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("should return the correct feature request count", async () => {
    // Setup
    mockPrisma.featureRequest.count.mockResolvedValue(5);

    const req = createMockRequest({
      method: "GET",
    });
    const response = await GET(req as any, { params: { id: userId } } as any);

    // Assertions
    expect(response.status).toBe(200);
    expect(response.data).toEqual({ count: 5 });
    expect(mockPrisma.featureRequest.count).toHaveBeenCalledWith({
      where: { userId },
    });
  });

  it("should return zero when user has no feature requests", async () => {
    // Setup
    mockPrisma.featureRequest.count.mockResolvedValue(0);

    const req = createMockRequest({
      method: "GET",
    });
    const response = await GET(req as any, { params: { id: userId } } as any);

    // Assertions
    expect(response.status).toBe(200);
    expect(response.data).toEqual({ count: 0 });
    expect(mockPrisma.featureRequest.count).toHaveBeenCalledWith({
      where: { userId },
    });
  });

  it("should handle database errors", async () => {
    // Setup
    mockPrisma.featureRequest.count.mockRejectedValue(
      new Error("Database error")
    );

    const req = createMockRequest({
      method: "GET",
    });
    const response = await GET(req as any, { params: { id: userId } } as any);

    // Assertions
    expect(response.status).toBe(500);
    expect(response.data.message).toBe("Failed to fetch feature request count");
  });
});
