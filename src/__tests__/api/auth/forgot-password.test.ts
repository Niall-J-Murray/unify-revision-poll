import { NextResponse } from "next/server";
import { mockPrisma } from "../../helpers/prisma-mock";
import { createMockRequest } from "../../helpers/api-test-helpers-fixed";

// Mock crypto
jest.mock("crypto", () => ({
  randomBytes: jest.fn(() => ({
    toString: jest.fn(() => "mock-random-token"),
  })),
  createHash: jest.fn(() => ({
    update: jest.fn(() => ({
      digest: jest.fn(() => "mock-hashed-token"),
    })),
  })),
}));

// Mock dependencies
jest.mock("@/lib/prisma", () => ({
  prisma: mockPrisma,
}));

// Mock email sending
jest.mock("@/lib/email", () => ({
  sendPasswordResetEmail: jest.fn(),
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

// Import the POST handler after mocking dependencies to avoid initialization issues
import { POST } from "@/app/api/auth/forgot-password/route";
import { sendPasswordResetEmail } from "@/lib/email";

describe("Forgot Password API", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  const mockUser = {
    id: "user-123",
    email: "test@example.com",
    name: "Test User",
  };

  it("should send a password reset email when user exists", async () => {
    // Mock user exists
    mockPrisma.user.findUnique.mockResolvedValue(mockUser);
    mockPrisma.user.update.mockResolvedValue({ ...mockUser });

    const req = createMockRequest({
      method: "POST",
      body: { email: "test@example.com" },
    });
    const response = await POST(req as any);

    // Verify response
    expect(response.status).toBe(200);
    const data = await response.json();
    expect(data.success).toBe(true);
    expect(data.message).toBe("Password reset email sent");

    // Verify user was updated with reset token
    expect(mockPrisma.user.update).toHaveBeenCalledWith({
      where: { id: mockUser.id },
      data: expect.objectContaining({
        resetPasswordToken: "mock-hashed-token",
        resetPasswordExpires: expect.any(Date),
      }),
    });

    // Verify email was sent
    expect(sendPasswordResetEmail).toHaveBeenCalledWith(
      "test@example.com",
      "mock-random-token"
    );
  });

  it("should return success even when user does not exist (security)", async () => {
    // Mock user does not exist
    mockPrisma.user.findUnique.mockResolvedValue(null);

    const req = createMockRequest({
      method: "POST",
      body: { email: "nonexistent@example.com" },
    });
    const response = await POST(req as any);

    // Verify response is still success (for security reasons)
    expect(response.status).toBe(200);
    const data = await response.json();
    expect(data.success).toBe(true);
    expect(data.message).toBe(
      "If your email is registered, you will receive a password reset link."
    );

    // Verify no token update or email was sent
    expect(mockPrisma.user.update).not.toHaveBeenCalled();
    expect(sendPasswordResetEmail).not.toHaveBeenCalled();
  });

  it("should handle missing email in request", async () => {
    const req = createMockRequest({
      method: "POST",
      body: {},
    });
    const response = await POST(req as any);

    // Check for success response (for security reasons)
    expect(response.status).toBe(200);
    const data = await response.json();
    expect(data.success).toBe(true);
    expect(data.message).toBe(
      "If your email is registered, you will receive a password reset link."
    );

    // No database operations or emails should occur
    expect(mockPrisma.user.findUnique).not.toHaveBeenCalled();
    expect(mockPrisma.user.update).not.toHaveBeenCalled();
    expect(sendPasswordResetEmail).not.toHaveBeenCalled();
  });

  it("should handle database errors gracefully", async () => {
    // Mock database error
    mockPrisma.user.findUnique.mockRejectedValue(
      new Error("Database connection error")
    );

    const req = createMockRequest({
      method: "POST",
      body: { email: "test@example.com" },
    });
    const response = await POST(req as any);

    // Should return error
    expect(response.status).toBe(500);
    const data = await response.json();
    expect(data.success).toBe(false);
    expect(data.message).toBe("Failed to process request");
  });

  it("should handle email sending errors gracefully", async () => {
    // Mock user exists but email sending fails
    mockPrisma.user.findUnique.mockResolvedValue(mockUser);
    mockPrisma.user.update.mockResolvedValue({ ...mockUser });
    (sendPasswordResetEmail as jest.Mock).mockRejectedValue(
      new Error("Email sending failed")
    );

    const req = createMockRequest({
      method: "POST",
      body: { email: "test@example.com" },
    });
    const response = await POST(req as any);

    // Should return error
    expect(response.status).toBe(500);
    const data = await response.json();
    expect(data.success).toBe(false);
    expect(data.message).toBe("Failed to process request");

    // Verify token was still created but email failed
    expect(mockPrisma.user.update).toHaveBeenCalled();
    expect(sendPasswordResetEmail).toHaveBeenCalled();
  });

  it("should handle JSON parsing errors", async () => {
    // Create a request that will throw during JSON parsing
    const req = createMockRequest({
      method: "POST",
      jsonError: new Error("Invalid JSON"),
    });
    const response = await POST(req as any);

    // Should return error
    expect(response.status).toBe(500);
    const data = await response.json();
    expect(data.success).toBe(false);
    expect(data.message).toBe("Failed to process request");
  });
});
