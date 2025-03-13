import { NextRequest, NextResponse } from "next/server";
import { mockPrisma } from "../../helpers/prisma-mock";
import * as crypto from "crypto";

// Mock dependencies
jest.mock("@/lib/prisma", () => ({
  prisma: mockPrisma,
}));

// Mock crypto
jest.mock("crypto", () => ({
  createHash: jest.fn().mockReturnValue({
    update: jest.fn().mockReturnThis(),
    digest: jest.fn().mockReturnValue("hashed-token-123"),
  }),
}));

// Import the route handler after mocking dependencies
import { GET } from "@/app/api/auth/verify-reset-token/route";

describe("Verify Reset Token API", () => {
  beforeEach(() => {
    jest.clearAllMocks();

    // Mock NextResponse.json
    jest.spyOn(NextResponse, "json").mockImplementation((data, options) => {
      return {
        status: options?.status || 200,
        json: async () => data,
        ...data,
      } as any;
    });
  });

  it("should return 400 if token is missing", async () => {
    // Create request with missing token
    const req = new NextRequest(
      new URL("http://localhost:3000/api/auth/verify-reset-token")
    );

    const response = await GET(req);

    // Verify response
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      valid: false,
      message: "Missing token",
    });
  });

  it("should return 400 if token is invalid or expired", async () => {
    // Mock user not found
    mockPrisma.user.findFirst.mockResolvedValueOnce(null);

    // Create request with token
    const req = new NextRequest(
      new URL(
        "http://localhost:3000/api/auth/verify-reset-token?token=invalid-token"
      )
    );

    const response = await GET(req);

    // Verify crypto was called with correct parameters
    expect(crypto.createHash).toHaveBeenCalledWith("sha256");

    // Verify Prisma was called with correct parameters
    expect(mockPrisma.user.findFirst).toHaveBeenCalledWith({
      where: {
        resetPasswordToken: "hashed-token-123",
        resetPasswordExpires: {
          gt: expect.any(Date),
        },
      },
    });

    // Verify response
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      valid: false,
      message: "Invalid or expired token",
    });
  });

  it("should return 200 if token is valid", async () => {
    // Mock user found
    mockPrisma.user.findFirst.mockResolvedValueOnce({
      id: "user-123",
      email: "user@example.com",
      resetPasswordToken: "hashed-token-123",
      resetPasswordExpires: new Date(Date.now() + 3600000), // 1 hour in the future
    });

    // Create request with token
    const req = new NextRequest(
      new URL(
        "http://localhost:3000/api/auth/verify-reset-token?token=valid-token"
      )
    );

    const response = await GET(req);

    // Verify response
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      valid: true,
    });
  });

  it("should return 500 on database error", async () => {
    // Mock database error
    mockPrisma.user.findFirst.mockRejectedValueOnce(
      new Error("Database error")
    );

    // Create request with token
    const req = new NextRequest(
      new URL(
        "http://localhost:3000/api/auth/verify-reset-token?token=some-token"
      )
    );

    // Mock console.error to prevent test output pollution
    jest.spyOn(console, "error").mockImplementation(() => {});

    const response = await GET(req);

    // Verify error was logged
    expect(console.error).toHaveBeenCalledWith(
      "Token verification error:",
      expect.any(Error)
    );

    // Verify response
    expect(response.status).toBe(500);
    expect(await response.json()).toEqual({
      valid: false,
      message: "Failed to verify token",
    });
  });
});
