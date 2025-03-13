import { NextRequest, NextResponse } from "next/server";
import { mockPrisma } from "../../helpers/prisma-mock";
import * as crypto from "crypto";
import bcrypt from "bcryptjs";

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

// Mock bcrypt
jest.mock("bcryptjs", () => ({
  hash: jest.fn().mockResolvedValue("hashed-password-123"),
}));

// Import the route handler after mocking dependencies
import { POST } from "@/app/api/auth/reset-password/route";

describe("Reset Password API", () => {
  const mockToken = "valid-reset-token";
  const mockHashedToken = crypto
    .createHash("sha256")
    .update(mockToken)
    .digest("hex");
  const mockUserId = "user-123";

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
      new URL("http://localhost:3000/api/auth/reset-password"),
      {
        method: "POST",
        body: JSON.stringify({ password: "newPassword123" }),
      }
    );

    // Mock req.json to return object with missing token
    jest
      .spyOn(req, "json")
      .mockResolvedValueOnce({ password: "newPassword123" });

    const response = await POST(req);

    // Verify response
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      success: false,
      message: "Missing required fields",
    });
  });

  it("should return 400 if password is missing", async () => {
    // Create request with missing password
    const req = new NextRequest(
      new URL("http://localhost:3000/api/auth/reset-password"),
      {
        method: "POST",
        body: JSON.stringify({ token: "reset-token-123" }),
      }
    );

    // Mock req.json to return object with missing password
    jest.spyOn(req, "json").mockResolvedValueOnce({ token: "reset-token-123" });

    const response = await POST(req);

    // Verify response
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      success: false,
      message: "Missing required fields",
    });
  });

  it("should return 400 if token is invalid or expired", async () => {
    // Mock user not found
    mockPrisma.user.findFirst.mockResolvedValueOnce(null);

    // Create request with token and password
    const req = new NextRequest(
      new URL("http://localhost:3000/api/auth/reset-password"),
      {
        method: "POST",
        body: JSON.stringify({
          token: "invalid-token",
          password: "newPassword123",
        }),
      }
    );

    // Mock req.json to return object with token and password
    jest.spyOn(req, "json").mockResolvedValueOnce({
      token: "invalid-token",
      password: "newPassword123",
    });

    const response = await POST(req);

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
      success: false,
      message: "Invalid or expired token",
    });
  });

  it("should reset password successfully with valid token", async () => {
    // Mock user found
    mockPrisma.user.findFirst.mockResolvedValueOnce({
      id: "user-123",
      email: "user@example.com",
      resetPasswordToken: "hashed-token-123",
      resetPasswordExpires: new Date(Date.now() + 3600000), // 1 hour in the future
    });

    // Mock user update
    mockPrisma.user.update.mockResolvedValueOnce({
      id: "user-123",
      email: "user@example.com",
    });

    // Create request with token and password
    const req = new NextRequest(
      new URL("http://localhost:3000/api/auth/reset-password"),
      {
        method: "POST",
        body: JSON.stringify({
          token: "valid-token",
          password: "newPassword123",
        }),
      }
    );

    // Mock req.json to return object with token and password
    jest.spyOn(req, "json").mockResolvedValueOnce({
      token: "valid-token",
      password: "newPassword123",
    });

    const response = await POST(req);

    // Verify bcrypt was called with correct parameters
    expect(bcrypt.hash).toHaveBeenCalledWith("newPassword123", 10);

    // Verify user was updated with new password and reset tokens cleared
    expect(mockPrisma.user.update).toHaveBeenCalledWith({
      where: { id: "user-123" },
      data: {
        password: "hashed-password-123",
        resetPasswordToken: null,
        resetPasswordExpires: null,
      },
    });

    // Verify response
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      success: true,
      message: "Password reset successful",
    });
  });

  it("should return 500 on database error", async () => {
    // Mock database error
    mockPrisma.user.findFirst.mockRejectedValueOnce(
      new Error("Database error")
    );

    // Create request with token and password
    const req = new NextRequest(
      new URL("http://localhost:3000/api/auth/reset-password"),
      {
        method: "POST",
        body: JSON.stringify({
          token: "some-token",
          password: "newPassword123",
        }),
      }
    );

    // Mock req.json to return object with token and password
    jest.spyOn(req, "json").mockResolvedValueOnce({
      token: "some-token",
      password: "newPassword123",
    });

    // Mock console.error to prevent test output pollution
    jest.spyOn(console, "error").mockImplementation(() => {});

    const response = await POST(req);

    // Verify error was logged
    expect(console.error).toHaveBeenCalledWith(
      "Reset password error:",
      expect.any(Error)
    );

    // Verify response
    expect(response.status).toBe(500);
    expect(await response.json()).toEqual({
      success: false,
      message: "Failed to reset password",
    });
  });
});
