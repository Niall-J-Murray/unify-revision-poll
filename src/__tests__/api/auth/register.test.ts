import { NextRequest, NextResponse } from "next/server";
import bcrypt from "bcryptjs";
import { mockPrisma } from "../../helpers/prisma-mock";
import { createMockRequest } from "../../helpers/api-test-helpers";
import * as emailService from "@/lib/email";

// Mock dependencies
jest.mock("@/lib/prisma", () => ({
  prisma: mockPrisma,
}));

jest.mock("bcryptjs", () => ({
  hash: jest.fn().mockResolvedValue("hashed-password-mock"),
}));

jest.mock("@/lib/email", () => ({
  sendVerificationEmail: jest.fn().mockResolvedValue(true),
}));

// Import the route handler after mocking dependencies
import { POST } from "@/app/api/auth/register/route";

describe("Register API", () => {
  // Reset all mocks before each test
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("should return 400 if required fields are missing", async () => {
    // Test missing name
    const reqWithoutName = createMockRequest({
      method: "POST",
      body: { email: "test@example.com", password: "Password123!" },
    });

    const responseWithoutName = await POST(reqWithoutName);
    expect(responseWithoutName.status).toBe(400);
    const dataWithoutName = await responseWithoutName.json();
    expect(dataWithoutName.success).toBe(false);
    expect(dataWithoutName.message).toContain("required");

    // Test missing email
    const reqWithoutEmail = createMockRequest({
      method: "POST",
      body: { name: "Test User", password: "Password123!" },
    });

    const responseWithoutEmail = await POST(reqWithoutEmail);
    expect(responseWithoutEmail.status).toBe(400);
    const dataWithoutEmail = await responseWithoutEmail.json();
    expect(dataWithoutEmail.success).toBe(false);
    expect(dataWithoutEmail.message).toContain("required");

    // Test missing password
    const reqWithoutPassword = createMockRequest({
      method: "POST",
      body: { name: "Test User", email: "test@example.com" },
    });

    const responseWithoutPassword = await POST(reqWithoutPassword);
    expect(responseWithoutPassword.status).toBe(400);
    const dataWithoutPassword = await responseWithoutPassword.json();
    expect(dataWithoutPassword.success).toBe(false);
    expect(dataWithoutPassword.message).toContain("required");
  });

  it("should return 400 if password is too weak", async () => {
    const req = createMockRequest({
      method: "POST",
      body: { name: "Test User", email: "test@example.com", password: "weak" },
    });

    const response = await POST(req);
    expect(response.status).toBe(400);
    const data = await response.json();
    expect(data.success).toBe(false);
    expect(data.message).toContain("Password");
  });

  it("should return 400 if email already exists", async () => {
    // Mock finding existing user
    mockPrisma.user.findUnique.mockResolvedValueOnce({
      id: "existing-user",
      email: "existing@example.com",
    });

    const req = createMockRequest({
      method: "POST",
      body: {
        name: "Test User",
        email: "existing@example.com",
        password: "Password123!",
      },
    });

    const response = await POST(req);
    expect(response.status).toBe(400);
    const data = await response.json();
    expect(data.success).toBe(false);
    expect(data.message).toContain("already in use");
  });

  it("should register a new user successfully", async () => {
    // Mock user not found (email not taken)
    mockPrisma.user.findUnique.mockResolvedValueOnce(null);

    // Mock creating a new user
    mockPrisma.user.create.mockResolvedValueOnce({
      id: "new-user",
      name: "Test User",
      email: "test@example.com",
      emailVerificationToken: "verification-token-mock",
      emailVerificationExpires: new Date(Date.now() + 24 * 60 * 60 * 1000),
    });

    const req = createMockRequest({
      method: "POST",
      body: {
        name: "Test User",
        email: "test@example.com",
        password: "Password123!",
      },
    });

    const response = await POST(req);
    expect(response.status).toBe(201);
    const data = await response.json();
    expect(data.success).toBe(true);
    expect(data.message).toContain("Registration successful");

    // Verify bcrypt was called
    expect(bcrypt.hash).toHaveBeenCalledWith("Password123!", 10);

    // Verify user was created
    expect(mockPrisma.user.create).toHaveBeenCalledTimes(1);
    expect(mockPrisma.user.create.mock.calls[0][0].data).toMatchObject({
      name: "Test User",
      email: "test@example.com",
      password: "hashed-password-mock",
    });

    // Verify email was sent
    expect(emailService.sendVerificationEmail).toHaveBeenCalledTimes(1);
    expect(emailService.sendVerificationEmail).toHaveBeenCalledWith(
      "test@example.com",
      expect.any(String)
    );
  });

  it("should handle database errors gracefully", async () => {
    // Mock user not found but throw error on create
    mockPrisma.user.findUnique.mockResolvedValueOnce(null);
    mockPrisma.user.create.mockRejectedValueOnce(new Error("Database error"));

    const req = createMockRequest({
      method: "POST",
      body: {
        name: "Test User",
        email: "test@example.com",
        password: "Password123!",
      },
    });

    const response = await POST(req);
    expect(response.status).toBe(500);
    const data = await response.json();
    expect(data.success).toBe(false);
    expect(data.message).toContain("Registration failed");
  });

  it("should handle email sending errors gracefully", async () => {
    // Mock user not found (email not taken)
    mockPrisma.user.findUnique.mockResolvedValueOnce(null);

    // Mock creating a new user
    mockPrisma.user.create.mockResolvedValueOnce({
      id: "new-user",
      name: "Test User",
      email: "test@example.com",
      emailVerificationToken: "verification-token-mock",
      emailVerificationExpires: new Date(Date.now() + 24 * 60 * 60 * 1000),
    });

    // Mock email sending failure
    (emailService.sendVerificationEmail as jest.Mock).mockRejectedValueOnce(
      new Error("Email sending failed")
    );

    const req = createMockRequest({
      method: "POST",
      body: {
        name: "Test User",
        email: "test@example.com",
        password: "Password123!",
      },
    });

    const response = await POST(req);

    // User should still be created even if email fails
    expect(response.status).toBe(201);
    const data = await response.json();
    expect(data.success).toBe(true);
    expect(data.message).toContain("Registration successful");
  });
});
