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

// Mock NextResponse.redirect
jest.mock("next/server", () => {
  const originalModule = jest.requireActual("next/server");
  return {
    ...originalModule,
    NextResponse: {
      ...originalModule.NextResponse,
      redirect: jest.fn().mockImplementation((url) => ({
        url,
        status: 302,
        headers: new Headers({ Location: url.toString() }),
      })),
    },
  };
});

// Import the route handler after mocking dependencies
import {
  GET,
  generateVerificationToken,
} from "@/app/api/auth/verify-email/route";

describe("Verify Email API", () => {
  const mockToken = "valid-verification-token";
  const mockUserId = "user-123";

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("should redirect to login with error if token is missing", async () => {
    // Create request with missing token
    const req = new NextRequest(
      new URL("http://localhost:3000/api/auth/verify-email")
    );

    const response = await GET(req);

    // Verify redirect
    expect(NextResponse.redirect).toHaveBeenCalledWith(
      expect.objectContaining({
        pathname: "/login",
        search: "?error=invalid-token",
      })
    );

    // Verify response
    expect(response.headers.get("Location")).toContain(
      "/login?error=invalid-token"
    );
  });

  it("should redirect to login with error if token is invalid or expired", async () => {
    // Mock user not found
    mockPrisma.user.findFirst.mockResolvedValueOnce(null);

    // Create request with token
    const req = new NextRequest(
      new URL(`http://localhost:3000/api/auth/verify-email?token=invalid-token`)
    );

    const response = await GET(req);

    // Verify Prisma was called with correct parameters
    expect(mockPrisma.user.findFirst).toHaveBeenCalledWith({
      where: {
        emailVerificationToken: "invalid-token",
        emailVerificationExpires: {
          gt: expect.any(Date),
        },
      },
    });

    // Verify redirect
    expect(NextResponse.redirect).toHaveBeenCalledWith(
      expect.objectContaining({
        pathname: "/login",
        search: "?error=invalid-token",
      })
    );

    // Verify response
    expect(response.headers.get("Location")).toContain(
      "/login?error=invalid-token"
    );
  });

  it("should verify email successfully with valid token", async () => {
    // Mock user found
    mockPrisma.user.findFirst.mockResolvedValueOnce({
      id: mockUserId,
      email: "user@example.com",
      emailVerificationToken: mockToken,
      emailVerificationExpires: new Date(Date.now() + 3600000), // 1 hour in the future
    });

    // Mock user update
    mockPrisma.user.update.mockResolvedValueOnce({
      id: mockUserId,
      email: "user@example.com",
    });

    // Create request with token
    const req = new NextRequest(
      new URL(`http://localhost:3000/api/auth/verify-email?token=${mockToken}`)
    );

    const response = await GET(req);

    // Verify user was updated as verified
    expect(mockPrisma.user.update).toHaveBeenCalledWith({
      where: { id: mockUserId },
      data: {
        emailVerified: expect.any(Date),
        emailVerificationToken: null,
        emailVerificationExpires: null,
      },
    });

    // Verify redirect
    expect(NextResponse.redirect).toHaveBeenCalledWith(
      expect.objectContaining({
        pathname: "/login",
        search: "?verified=true",
      })
    );

    // Verify response
    expect(response.headers.get("Location")).toContain("/login?verified=true");
  });

  it("should redirect to login with error on database error", async () => {
    // Mock database error
    mockPrisma.user.findFirst.mockRejectedValueOnce(
      new Error("Database error")
    );

    // Create request with token
    const req = new NextRequest(
      new URL(`http://localhost:3000/api/auth/verify-email?token=${mockToken}`)
    );

    // Mock console.error to prevent test output pollution
    jest.spyOn(console, "error").mockImplementation(() => {});

    const response = await GET(req);

    // Verify error was logged
    expect(console.error).toHaveBeenCalledWith(
      "Email verification error:",
      expect.any(Error)
    );

    // Verify redirect
    expect(NextResponse.redirect).toHaveBeenCalledWith(
      expect.objectContaining({
        pathname: "/login",
        search: "?error=verification-failed",
      })
    );

    // Verify response
    expect(response.headers.get("Location")).toContain(
      "/login?error=verification-failed"
    );
  });

  it("should generate a verification token", () => {
    const email = "user@example.com";
    const token = generateVerificationToken(email);

    // Verify crypto was called with correct parameters
    expect(crypto.createHash).toHaveBeenCalledWith("sha256");

    // Verify token is returned
    expect(token).toBe("hashed-token-123");
  });
});
