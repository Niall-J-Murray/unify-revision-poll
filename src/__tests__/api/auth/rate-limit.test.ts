import { NextRequest, NextResponse } from "next/server";
import { POST } from "@/app/api/auth/rate-limit/route";
import { checkLoginRateLimit, resetLoginAttempts } from "@/lib/rate-limiter";

// Mock dependencies
jest.mock("@/lib/rate-limiter", () => ({
  checkLoginRateLimit: jest.fn(),
  resetLoginAttempts: jest.fn(),
}));

describe("Rate Limit API", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  // Helper to create mock request
  const createMockRequest = (body: any, headers = {}) => {
    return {
      json: jest.fn().mockResolvedValue(body),
      headers: {
        get: jest.fn((name) => headers[name] || null),
      },
    } as unknown as NextRequest;
  };

  it("should reset rate limit on successful login", async () => {
    const req = createMockRequest({
      email: "test@example.com",
      success: true,
    });

    const response = await POST(req);
    const responseData = await response.json();

    // Verify response
    expect(response.status).toBe(200);
    expect(responseData).toEqual({
      success: true,
    });

    // Verify resetLoginAttempts was called with the email
    expect(resetLoginAttempts).toHaveBeenCalledWith("test@example.com");
    expect(checkLoginRateLimit).not.toHaveBeenCalled();
  });

  it("should check rate limit on failed login", async () => {
    // Mock rate limit check response
    const resetTime = new Date();
    const mockResult = {
      success: true,
      remainingAttempts: 4,
      resetTime,
    };
    (checkLoginRateLimit as jest.Mock).mockReturnValue(mockResult);

    const req = createMockRequest({
      email: "test@example.com",
      success: false,
    });

    const response = await POST(req);
    const responseData = await response.json();

    // Verify response
    expect(response.status).toBe(200);
    expect(responseData.success).toBe(true);
    expect(responseData.remainingAttempts).toBe(4);
    expect(responseData.resetTime).toBeDefined();

    // Verify checkLoginRateLimit was called with the email
    expect(checkLoginRateLimit).toHaveBeenCalledWith("test@example.com");
    expect(resetLoginAttempts).not.toHaveBeenCalled();
  });

  it("should return rate limit exceeded response", async () => {
    // Mock rate limit exceeded
    const resetTime = new Date();
    const mockResult = {
      success: false,
      message: "Too many login attempts. Please try again later.",
      resetTime,
    };
    (checkLoginRateLimit as jest.Mock).mockReturnValue(mockResult);

    const req = createMockRequest({
      email: "test@example.com",
      success: false,
    });

    const response = await POST(req);
    const responseData = await response.json();

    // Verify response
    expect(response.status).toBe(200); // The route doesn't set a 429 status
    expect(responseData.success).toBe(false);
    expect(responseData.message).toBe(
      "Too many login attempts. Please try again later."
    );
    expect(responseData.resetTime).toBeDefined();

    // Verify checkLoginRateLimit was called with the email
    expect(checkLoginRateLimit).toHaveBeenCalledWith("test@example.com");
    expect(resetLoginAttempts).not.toHaveBeenCalled();
  });

  it("should use IP address if email is not provided", async () => {
    // Mock rate limit check response
    const resetTime = new Date();
    const mockResult = {
      success: true,
      remainingAttempts: 4,
      resetTime,
    };
    (checkLoginRateLimit as jest.Mock).mockReturnValue(mockResult);

    const req = createMockRequest(
      { success: false }, // No email
      { "x-forwarded-for": "192.168.1.1" } // IP in headers
    );

    const response = await POST(req);
    const responseData = await response.json();

    // Verify response
    expect(response.status).toBe(200);
    expect(responseData.success).toBe(true);
    expect(responseData.remainingAttempts).toBe(4);
    expect(responseData.resetTime).toBeDefined();

    // Verify checkLoginRateLimit was called with the IP
    expect(checkLoginRateLimit).toHaveBeenCalledWith("192.168.1.1");
  });

  it("should handle missing body gracefully", async () => {
    const req = {
      json: jest.fn().mockRejectedValue(new Error("Invalid JSON")),
      headers: {
        get: jest.fn(() => "192.168.1.1"),
      },
    } as unknown as NextRequest;

    const response = await POST(req);

    // Should return error
    expect(response.status).toBe(500);
    expect(await response.json()).toEqual({
      success: false,
      message: "Internal server error",
    });
  });

  it("should handle other errors gracefully", async () => {
    // Mock rate limit check to throw error
    (checkLoginRateLimit as jest.Mock).mockImplementation(() => {
      throw new Error("Unexpected error");
    });

    const req = createMockRequest({
      email: "test@example.com",
      success: false,
    });

    const response = await POST(req);

    // Should return error
    expect(response.status).toBe(500);
    expect(await response.json()).toEqual({
      success: false,
      message: "Internal server error",
    });
  });
});
