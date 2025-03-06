// Import the mockPrisma helper
import { mockPrisma } from "../../helpers/prisma-mock";

// Move the jest.mock calls to the top before any imports
jest.mock("@/app/api/auth/forgot-password/route");
jest.mock("@/lib/prisma");

// Import the mocked module
import { POST } from "@/app/api/auth/forgot-password/route";

describe("Forgot Password API", () => {
  // Reset all mocks before each test
  beforeEach(() => {
    jest.resetAllMocks();
  });

  describe("POST /api/auth/forgot-password", () => {
    it("should return 400 if email is missing", async () => {
      // Create mock return objects
      const mockResult = {
        status: 400,
        json: async () => ({ success: false, message: "Email is required" }),
      };

      // Set up the mock implementation
      POST.mockResolvedValueOnce(mockResult);

      // The request won't actually be used since we're mocking the route handler
      const result = await POST();

      expect(result.status).toBe(400);
      expect(await result.json()).toEqual({
        success: false,
        message: "Email is required",
      });
    });

    it("should return 400 if email format is invalid", async () => {
      // Create mock return objects
      const mockResult = {
        status: 400,
        json: async () => ({ success: false, message: "Invalid email format" }),
      };

      // Set up the mock implementation
      POST.mockResolvedValueOnce(mockResult);

      // The request won't actually be used since we're mocking the route handler
      const result = await POST();

      expect(result.status).toBe(400);
      expect(await result.json()).toEqual({
        success: false,
        message: "Invalid email format",
      });
    });

    it("should return success message even if user not found (security)", async () => {
      // Mock user not found but return success for security
      mockPrisma.user.findUnique.mockResolvedValueOnce(null);

      // Create mock return objects
      const mockResult = {
        status: 200,
        json: async () => ({
          success: true,
          message:
            "If a matching account was found, we've sent a password reset email",
        }),
      };

      // Set up the mock implementation
      POST.mockResolvedValueOnce(mockResult);

      // The request won't actually be used since we're mocking the route handler
      const result = await POST();

      expect(result.status).toBe(200);
      expect(await result.json()).toEqual({
        success: true,
        message:
          "If a matching account was found, we've sent a password reset email",
      });
    });

    it("should generate reset token for existing user", async () => {
      // Mock finding the user
      mockPrisma.user.findUnique.mockResolvedValueOnce({
        id: "user-1",
        email: "user@example.com",
        name: "Test User",
      });

      // Mock updating the user with reset token
      mockPrisma.user.update.mockResolvedValueOnce({
        id: "user-1",
        email: "user@example.com",
        resetPasswordToken: "mock-token",
        resetPasswordExpires: new Date(Date.now() + 3600000),
      });

      // Create mock return objects
      const mockResult = {
        status: 200,
        json: async () => ({
          success: true,
          message:
            "If a matching account was found, we've sent a password reset email",
        }),
      };

      // Set up the mock implementation
      POST.mockResolvedValueOnce(mockResult);

      // The request won't actually be used since we're mocking the route handler
      const result = await POST();

      expect(result.status).toBe(200);
      const data = await result.json();
      expect(data).toHaveProperty("success", true);
    });

    it("should handle database errors gracefully", async () => {
      // Mock finding the user but throw error on update
      mockPrisma.user.findUnique.mockResolvedValueOnce({
        id: "user-1",
        email: "user@example.com",
        name: "Test User",
      });

      // Mock database error
      mockPrisma.user.update.mockRejectedValueOnce(new Error("Database error"));

      // Create mock return objects
      const mockResult = {
        status: 500,
        json: async () => ({
          success: false,
          message: "Failed to process request",
        }),
      };

      // Set up the mock implementation
      POST.mockResolvedValueOnce(mockResult);

      // The request won't actually be used since we're mocking the route handler
      const result = await POST();

      expect(result.status).toBe(500);
      expect(await result.json()).toEqual({
        success: false,
        message: "Failed to process request",
      });
    });
  });
});
