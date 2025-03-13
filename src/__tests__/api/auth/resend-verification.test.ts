import { NextRequest, NextResponse } from "next/server";
import { mockPrisma } from "../../helpers/prisma-mock";
import { getServerSession } from "next-auth/next";
import * as emailModule from "@/lib/email";

// Mock dependencies
jest.mock("@/lib/prisma", () => ({
  prisma: mockPrisma,
}));

// Mock next-auth
jest.mock("next-auth/next", () => ({
  getServerSession: jest.fn(),
}));

// Mock email service
jest.mock("@/lib/email", () => ({
  sendVerificationEmail: jest.fn().mockResolvedValue(undefined),
}));

// Mock verify-email route for token generation
jest.mock("@/app/api/auth/verify-email/route", () => ({
  generateVerificationToken: jest
    .fn()
    .mockReturnValue("mock-verification-token"),
}));

// Mock authOptions
jest.mock("@/app/api/auth/[...nextauth]/route", () => ({
  authOptions: {},
}));

// Import the route handler after mocking dependencies
import { POST } from "@/app/api/auth/resend-verification/route";

describe("Resend Verification API", () => {
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

  it("should return 401 if user is not authenticated", async () => {
    // Mock no session
    (getServerSession as jest.Mock).mockResolvedValueOnce(null);

    // Create request
    const req = new NextRequest(
      new URL("http://localhost:3000/api/auth/resend-verification"),
      {
        method: "POST",
        body: JSON.stringify({ email: "user@example.com" }),
      }
    );

    const response = await POST(req);

    // Verify response
    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({
      success: false,
      message: "Unauthorized",
    });
  });

  it("should return 401 if email does not match session user", async () => {
    // Mock session with different email
    (getServerSession as jest.Mock).mockResolvedValueOnce({
      user: {
        id: "user-123",
        email: "session-user@example.com",
      },
    });

    // Create request with different email
    const req = new NextRequest(
      new URL("http://localhost:3000/api/auth/resend-verification"),
      {
        method: "POST",
        body: JSON.stringify({ email: "different-user@example.com" }),
      }
    );

    // Mock req.json to return object with email
    jest.spyOn(req, "json").mockResolvedValueOnce({
      email: "different-user@example.com",
    });

    const response = await POST(req);

    // Verify response
    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({
      success: false,
      message: "Unauthorized",
    });
  });

  it("should return 404 if user is not found", async () => {
    // Mock session with matching email
    (getServerSession as jest.Mock).mockResolvedValueOnce({
      user: {
        id: "user-123",
        email: "user@example.com",
      },
    });

    // Mock user not found
    mockPrisma.user.findUnique.mockResolvedValueOnce(null);

    // Create request
    const req = new NextRequest(
      new URL("http://localhost:3000/api/auth/resend-verification"),
      {
        method: "POST",
        body: JSON.stringify({ email: "user@example.com" }),
      }
    );

    // Mock req.json to return object with email
    jest.spyOn(req, "json").mockResolvedValueOnce({
      email: "user@example.com",
    });

    const response = await POST(req);

    // Verify Prisma was called with correct parameters
    expect(mockPrisma.user.findUnique).toHaveBeenCalledWith({
      where: { email: "user@example.com" },
    });

    // Verify response
    expect(response.status).toBe(404);
    expect(await response.json()).toEqual({
      success: false,
      message: "User not found",
    });
  });

  it("should return 400 if email is already verified", async () => {
    // Mock session with matching email
    (getServerSession as jest.Mock).mockResolvedValueOnce({
      user: {
        id: "user-123",
        email: "user@example.com",
      },
    });

    // Mock user found with verified email
    mockPrisma.user.findUnique.mockResolvedValueOnce({
      id: "user-123",
      email: "user@example.com",
      emailVerified: new Date(),
    });

    // Create request
    const req = new NextRequest(
      new URL("http://localhost:3000/api/auth/resend-verification"),
      {
        method: "POST",
        body: JSON.stringify({ email: "user@example.com" }),
      }
    );

    // Mock req.json to return object with email
    jest.spyOn(req, "json").mockResolvedValueOnce({
      email: "user@example.com",
    });

    const response = await POST(req);

    // Verify response
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      success: false,
      message: "Email is already verified",
    });
  });

  it("should successfully resend verification email", async () => {
    // Mock session with matching email
    (getServerSession as jest.Mock).mockResolvedValueOnce({
      user: {
        id: "user-123",
        email: "user@example.com",
      },
    });

    // Mock user found with unverified email
    mockPrisma.user.findUnique.mockResolvedValueOnce({
      id: "user-123",
      email: "user@example.com",
      emailVerified: null,
    });

    // Mock user update
    mockPrisma.user.update.mockResolvedValueOnce({
      id: "user-123",
      email: "user@example.com",
    });

    // Create request
    const req = new NextRequest(
      new URL("http://localhost:3000/api/auth/resend-verification"),
      {
        method: "POST",
        body: JSON.stringify({ email: "user@example.com" }),
      }
    );

    // Mock req.json to return object with email
    jest.spyOn(req, "json").mockResolvedValueOnce({
      email: "user@example.com",
    });

    const response = await POST(req);

    // Verify user was updated with new token
    expect(mockPrisma.user.update).toHaveBeenCalledWith({
      where: { email: "user@example.com" },
      data: {
        emailVerificationToken: "mock-verification-token",
        emailVerificationExpires: expect.any(Date),
      },
    });

    // Verify email was sent
    expect(emailModule.sendVerificationEmail).toHaveBeenCalledWith(
      "user@example.com",
      "mock-verification-token"
    );

    // Verify response
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      success: true,
      message: "Verification email sent successfully",
    });
  });

  it("should return 500 on database error", async () => {
    // Mock session with matching email
    (getServerSession as jest.Mock).mockResolvedValueOnce({
      user: {
        id: "user-123",
        email: "user@example.com",
      },
    });

    // Mock database error
    mockPrisma.user.findUnique.mockRejectedValueOnce(
      new Error("Database error")
    );

    // Create request
    const req = new NextRequest(
      new URL("http://localhost:3000/api/auth/resend-verification"),
      {
        method: "POST",
        body: JSON.stringify({ email: "user@example.com" }),
      }
    );

    // Mock req.json to return object with email
    jest.spyOn(req, "json").mockResolvedValueOnce({
      email: "user@example.com",
    });

    // Mock console.error to prevent test output pollution
    jest.spyOn(console, "error").mockImplementation(() => {});

    const response = await POST(req);

    // Verify error was logged
    expect(console.error).toHaveBeenCalledWith(
      "Resend verification error:",
      expect.any(Error)
    );

    // Verify response
    expect(response.status).toBe(500);
    expect(await response.json()).toEqual({
      success: false,
      message: "Failed to send verification email",
    });
  });

  it("should return 500 on email sending error", async () => {
    // Mock session with matching email
    (getServerSession as jest.Mock).mockResolvedValueOnce({
      user: {
        id: "user-123",
        email: "user@example.com",
      },
    });

    // Mock user found with unverified email
    mockPrisma.user.findUnique.mockResolvedValueOnce({
      id: "user-123",
      email: "user@example.com",
      emailVerified: null,
    });

    // Mock user update
    mockPrisma.user.update.mockResolvedValueOnce({
      id: "user-123",
      email: "user@example.com",
    });

    // Mock email sending error
    (emailModule.sendVerificationEmail as jest.Mock).mockRejectedValueOnce(
      new Error("Email sending failed")
    );

    // Create request
    const req = new NextRequest(
      new URL("http://localhost:3000/api/auth/resend-verification"),
      {
        method: "POST",
        body: JSON.stringify({ email: "user@example.com" }),
      }
    );

    // Mock req.json to return object with email
    jest.spyOn(req, "json").mockResolvedValueOnce({
      email: "user@example.com",
    });

    // Mock console.error to prevent test output pollution
    jest.spyOn(console, "error").mockImplementation(() => {});

    const response = await POST(req);

    // Verify error was logged
    expect(console.error).toHaveBeenCalledWith(
      "Resend verification error:",
      expect.any(Error)
    );

    // Verify response
    expect(response.status).toBe(500);
    expect(await response.json()).toEqual({
      success: false,
      message: "Failed to send verification email",
    });
  });
});
