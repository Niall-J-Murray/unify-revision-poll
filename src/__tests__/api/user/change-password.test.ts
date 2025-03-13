import { mockPrisma } from "../../helpers/prisma-mock";
import {
  createMockRequest,
  mockAuthenticatedSession,
  mockUnauthenticatedSession,
} from "../../helpers/api-test-helpers";
import bcrypt from "bcryptjs";
import { getServerSession } from "next-auth/next";

// Mock dependencies
jest.mock("@/lib/prisma", () => ({
  prisma: mockPrisma,
}));

jest.mock("bcryptjs", () => ({
  compare: jest.fn(),
  hash: jest.fn(),
}));

// Mock NextAuth
jest.mock("next-auth/next", () => ({
  getServerSession: jest.fn(),
}));

// Mock authOptions
jest.mock("@/app/api/auth/[...nextauth]/route", () => ({
  authOptions: {
    adapter: {
      createUser: jest.fn(),
      getUser: jest.fn(),
      getUserByEmail: jest.fn(),
      updateUser: jest.fn(),
      deleteUser: jest.fn(),
      linkAccount: jest.fn(),
      unlinkAccount: jest.fn(),
      createSession: jest.fn(),
      getSessionAndUser: jest.fn(),
      updateSession: jest.fn(),
      deleteSession: jest.fn(),
      createVerificationToken: jest.fn(),
      useVerificationToken: jest.fn(),
    },
    providers: [],
    callbacks: {
      session: jest.fn(),
      jwt: jest.fn(),
    },
    secret: "test-secret",
  },
}));

// Import the API route handler after mocking dependencies
import { POST } from "@/app/api/user/change-password/route";

describe("Change Password API", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    // Mock authenticated session with email
    (getServerSession as jest.Mock).mockResolvedValue({
      user: {
        id: "mock-user-id",
        name: "Test User",
        email: "test@example.com",
        role: "USER",
      },
    });
  });

  it("should return 400 if current password is missing", async () => {
    mockAuthenticatedSession();

    const req = createMockRequest({
      method: "POST",
      body: {
        newPassword: "NewPassword123!",
      },
    });

    const response = await POST(req);
    expect(response.status).toBe(400);
    const data = await response.json();
    expect(data.success).toBe(false);
    expect(data.message).toContain("Missing required fields");
  });

  it("should return 400 if new password is missing", async () => {
    mockAuthenticatedSession();

    const req = createMockRequest({
      method: "POST",
      body: {
        currentPassword: "CurrentPassword123!",
      },
    });

    const response = await POST(req);
    expect(response.status).toBe(400);
    const data = await response.json();
    expect(data.success).toBe(false);
    expect(data.message).toContain("Missing required fields");
  });

  it("should return 400 if new password is too weak", async () => {
    mockAuthenticatedSession();

    const req = createMockRequest({
      method: "POST",
      body: {
        currentPassword: "CurrentPassword123!",
        newPassword: "weak",
      },
    });

    const response = await POST(req);
    expect(response.status).toBe(400);
    const data = await response.json();
    expect(data.success).toBe(false);
    expect(data.message).toContain("at least 8 characters");
  });

  it("should return 401 if user is not authenticated", async () => {
    mockUnauthenticatedSession();

    const req = createMockRequest({
      method: "POST",
      body: {
        currentPassword: "CurrentPassword123!",
        newPassword: "NewPassword123!",
      },
    });

    const response = await POST(req);
    expect(response.status).toBe(401);
    const data = await response.json();
    expect(data.success).toBe(false);
    expect(data.message).toBe("Unauthorized");
  });

  it("should return 400 if current password is incorrect", async () => {
    mockAuthenticatedSession();

    // Mock user retrieval
    mockPrisma.user.findUnique.mockResolvedValueOnce({
      id: "mock-user-id",
      password: "hashedPassword",
    });

    // Mock password comparison to fail
    (bcrypt.compare as jest.Mock).mockResolvedValueOnce(false);

    const req = createMockRequest({
      method: "POST",
      body: {
        currentPassword: "WrongPassword123!",
        newPassword: "NewPassword123!",
      },
    });

    const response = await POST(req);
    expect(response.status).toBe(400);
    const data = await response.json();
    expect(data.success).toBe(false);
    expect(data.message).toBe("Current password is incorrect");
  });

  it("should successfully change password", async () => {
    mockAuthenticatedSession();

    // Mock user retrieval
    mockPrisma.user.findUnique.mockResolvedValueOnce({
      id: "mock-user-id",
      password: "hashedPassword",
    });

    // Mock password comparison to succeed
    (bcrypt.compare as jest.Mock).mockResolvedValueOnce(true);

    // Mock password hashing
    (bcrypt.hash as jest.Mock).mockResolvedValueOnce("newHashedPassword");

    const req = createMockRequest({
      method: "POST",
      body: {
        currentPassword: "CurrentPassword123!",
        newPassword: "NewPassword123!",
      },
    });

    const response = await POST(req);
    expect(response.status).toBe(200);
    const data = await response.json();
    expect(data.success).toBe(true);
    expect(data.message).toBe("Password changed successfully");

    // Verify Prisma was called correctly
    expect(mockPrisma.user.update).toHaveBeenCalledWith({
      where: { id: "mock-user-id" },
      data: { password: "newHashedPassword" },
    });
  });

  it("should handle database errors", async () => {
    mockAuthenticatedSession();

    // Mock user retrieval to throw error
    mockPrisma.user.findUnique.mockRejectedValueOnce(
      new Error("Database error")
    );

    const req = createMockRequest({
      method: "POST",
      body: {
        currentPassword: "CurrentPassword123!",
        newPassword: "NewPassword123!",
      },
    });

    const response = await POST(req);
    expect(response.status).toBe(500);
    const data = await response.json();
    expect(data.success).toBe(false);
    expect(data.message).toBe("Failed to change password");
  });
});
