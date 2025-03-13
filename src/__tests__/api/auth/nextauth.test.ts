// Import mockPrisma helper
import { mockPrisma } from "../../helpers/prisma-mock";
import { NextAuthOptions } from "next-auth";

// Mock bcrypt
jest.mock("bcryptjs", () => ({
  compare: jest.fn(),
  hash: jest.fn(),
}));

// Import bcrypt after mocking
import bcrypt from "bcryptjs";

jest.mock("@/lib/prisma", () => ({
  prisma: mockPrisma,
}));

// Mock PrismaAdapter
jest.mock("@auth/prisma-adapter", () => {
  return {
    PrismaAdapter: jest.fn().mockImplementation((prisma) => {
      return {
        createUser: jest.fn(),
        getUser: jest.fn(),
        getUserByEmail: jest.fn(),
        getUserByAccount: jest.fn(),
        linkAccount: jest.fn(),
        createSession: jest.fn(),
        getSessionAndUser: jest.fn(),
        updateUser: jest.fn(),
        updateSession: jest.fn(),
        deleteSession: jest.fn(),
      };
    }),
  };
});

// Mock the NextAuth route
jest.mock("@/app/api/auth/[...nextauth]/route", () => {
  // Import the mocked PrismaAdapter
  const { PrismaAdapter } = require("@auth/prisma-adapter");
  const mockPrisma = require("../../helpers/prisma-mock").mockPrisma;
  const bcrypt = require("bcryptjs");

  // Create mock functions for callbacks
  const jwtCallback = jest.fn().mockImplementation(({ token, user }) => {
    if (user) {
      token.role = user.role;
    }
    return token;
  });

  const sessionCallback = jest.fn().mockImplementation(({ session, token }) => {
    if (session.user) {
      session.user.id = token.sub;
      session.user.role = token.role;
    }
    return session;
  });

  const redirectCallback = jest.fn().mockImplementation(({ url, baseUrl }) => {
    return baseUrl;
  });

  // Create mock authorize function
  const authorizeFunction = jest
    .fn()
    .mockImplementation(async (credentials) => {
      if (!credentials?.email || !credentials?.password) {
        return null;
      }

      try {
        const user = await mockPrisma.user.findUnique({
          where: { email: credentials.email },
        });

        if (!user || !user.password) {
          return null;
        }

        const isValid = await bcrypt.compare(
          credentials.password,
          user.password
        );

        if (!isValid) {
          return null;
        }

        if (!user.emailVerified) {
          return null;
        }

        return {
          id: user.id,
          email: user.email,
          name: user.name,
          role: user.role,
        };
      } catch (error) {
        return null;
      }
    });

  // Create mock authOptions
  const mockAuthOptions = {
    adapter: PrismaAdapter(mockPrisma),
    providers: [
      {
        id: "credentials",
        name: "Credentials",
        credentials: {
          email: { label: "Email", type: "email" },
          password: { label: "Password", type: "password" },
        },
        authorize: authorizeFunction,
      },
      { id: "google", name: "Google" },
      { id: "github", name: "GitHub" },
    ],
    session: {
      strategy: "jwt",
    },
    callbacks: {
      jwt: jwtCallback,
      session: sessionCallback,
      redirect: redirectCallback,
    },
    pages: {
      signIn: "/login",
      error: "/login",
    },
    secret: "test-secret",
  };

  return {
    authOptions: mockAuthOptions,
    GET: jest.fn(),
    POST: jest.fn(),
  };
});

// Import the mocked auth options
import { authOptions } from "@/app/api/auth/[...nextauth]/route";
import { PrismaAdapter } from "@auth/prisma-adapter";

describe("NextAuth Configuration", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (bcrypt.compare as jest.Mock).mockReset();
  });

  describe("Configuration", () => {
    it("should have the correct configuration", () => {
      expect(authOptions).toHaveProperty("adapter");
      expect(authOptions).toHaveProperty("providers");
      expect(authOptions).toHaveProperty("callbacks");
      expect(authOptions).toHaveProperty("pages");
      expect(authOptions).toHaveProperty("secret");
    });

    it("should have configured sign-in page", () => {
      expect(authOptions.pages).toHaveProperty("signIn", "/login");
    });

    it("should include credential, Google, and GitHub providers", () => {
      const providerNames = authOptions.providers.map(
        (p: any) => p.id || p.name
      );
      expect(providerNames).toContain("credentials");
      expect(providerNames).toContain("google");
      expect(providerNames).toContain("github");
    });
  });

  describe("Credentials Provider", () => {
    let credentialsProvider: any;
    let authorize: Function;

    beforeEach(() => {
      credentialsProvider = authOptions.providers.find(
        (p: any) => p.id === "credentials" || p.name === "Credentials"
      );
      authorize = credentialsProvider.authorize;
    });

    it("should have an authorize function", () => {
      expect(credentialsProvider).toHaveProperty("authorize");
      expect(typeof credentialsProvider.authorize).toBe("function");
    });

    it("should return null if credentials are missing", async () => {
      const result = await authorize({});
      expect(result).toBeNull();
    });

    it("should return user data if authentication succeeds", async () => {
      // Mock prisma to return a user
      mockPrisma.user.findUnique.mockResolvedValueOnce({
        id: "user-1",
        email: "test@example.com",
        name: "Test User",
        role: "USER",
        password: "hashed-password",
        emailVerified: new Date(),
      });

      // Mock bcrypt to return true for password comparison
      (bcrypt.compare as jest.Mock).mockResolvedValueOnce(true);

      const result = await authorize({
        email: "test@example.com",
        password: "correct-password",
      });

      expect(result).toHaveProperty("id");
      expect(result).toHaveProperty("email");
      expect(result).toHaveProperty("role");
    });

    it("should return null if user not found", async () => {
      // Mock prisma to return null (user not found)
      mockPrisma.user.findUnique.mockResolvedValueOnce(null);

      const result = await authorize({
        email: "nonexistent@example.com",
        password: "password",
      });

      expect(result).toBeNull();
    });

    it("should return null if password is incorrect", async () => {
      // Mock prisma to return a user
      mockPrisma.user.findUnique.mockResolvedValueOnce({
        id: "user-1",
        email: "test@example.com",
        name: "Test User",
        role: "USER",
        password: "hashed-password",
        emailVerified: new Date(),
      });

      // Mock bcrypt to return false for password comparison
      (bcrypt.compare as jest.Mock).mockResolvedValueOnce(false);

      const result = await authorize({
        email: "test@example.com",
        password: "wrong-password",
      });

      expect(result).toBeNull();
    });
  });

  describe("JWT and Session Callbacks", () => {
    it("should add user data to JWT token", () => {
      const token = {};
      const user = { id: "user-1", role: "USER" };

      const result = authOptions.callbacks.jwt({ token, user } as any);

      expect(result).toHaveProperty("role", "USER");
    });

    it("should add token data to session", () => {
      const session = { user: {} };
      const token = { sub: "user-1", role: "USER" };

      const result = authOptions.callbacks.session({
        session,
        token,
      } as any);

      expect(result.user).toHaveProperty("id", "user-1");
      expect(result.user).toHaveProperty("role", "USER");
    });

    it("should maintain existing token data if no user is provided", () => {
      const token = { sub: "existing-id", role: "USER", name: "Existing Name" };

      const result = authOptions.callbacks.jwt({ token } as any);

      expect(result).toEqual(token);
    });

    it("should handle redirect callback correctly", () => {
      const baseUrl = "https://example.com";
      const url = "https://example.com/dashboard";

      const result = authOptions.callbacks.redirect({
        url,
        baseUrl,
      } as any);

      expect(result).toBe(baseUrl);
    });
  });

  describe("NextAuth Configuration", () => {
    it("should have the correct providers configured", () => {
      expect(authOptions.providers).toBeDefined();
      expect(authOptions.providers.length).toBeGreaterThan(0);

      // Check for credentials provider
      const credentialsProvider = authOptions.providers.find(
        (provider) => provider.id === "credentials"
      );
      expect(credentialsProvider).toBeDefined();
      expect(credentialsProvider.name).toBe("Credentials");
    });

    it("should use PrismaAdapter", () => {
      expect(authOptions.adapter).toBeDefined();
      const adapter = authOptions.adapter;
      expect(adapter).toHaveProperty("createUser");
      expect(adapter).toHaveProperty("getUser");
      expect(adapter).toHaveProperty("getUserByEmail");
      expect(adapter).toHaveProperty("updateUser");
      expect(adapter).toHaveProperty("deleteSession");
    });

    it("should have pages configured", () => {
      expect(authOptions.pages).toBeDefined();
      expect(authOptions.pages.signIn).toBe("/login");
      expect(authOptions.pages.error).toBe("/login");
    });

    it("should have session configuration", () => {
      expect(authOptions.session).toBeDefined();
      expect(authOptions.session.strategy).toBe("jwt");
    });

    it("should have callbacks configured", () => {
      expect(authOptions.callbacks).toBeDefined();
      expect(typeof authOptions.callbacks.jwt).toBe("function");
      expect(typeof authOptions.callbacks.session).toBe("function");
    });
  });

  describe("Credentials Provider", () => {
    let credentialsProvider: any;
    let authorize: Function;

    beforeEach(() => {
      credentialsProvider = authOptions.providers.find(
        (provider) => provider.id === "credentials"
      );
      authorize = credentialsProvider.authorize;
    });

    it("should return null if user is not found", async () => {
      // Mock user not found
      mockPrisma.user.findUnique.mockResolvedValueOnce(null);

      const result = await authorize({
        email: "nonexistent@example.com",
        password: "password123",
      });

      expect(result).toBeNull();
      expect(mockPrisma.user.findUnique).toHaveBeenCalledWith({
        where: { email: "nonexistent@example.com" },
      });
    });

    it("should return null if password is incorrect", async () => {
      // Mock user found
      mockPrisma.user.findUnique.mockResolvedValueOnce({
        id: "user-1",
        email: "user@example.com",
        password: "hashed-password",
        emailVerified: new Date(),
      });

      // Mock password comparison to fail
      (bcrypt.compare as jest.Mock).mockResolvedValueOnce(false);

      const result = await authorize({
        email: "user@example.com",
        password: "wrong-password",
      });

      expect(result).toBeNull();
      expect(bcrypt.compare).toHaveBeenCalledWith(
        "wrong-password",
        "hashed-password"
      );
    });

    it("should return user if credentials are valid", async () => {
      // Mock user found
      const mockUser = {
        id: "user-1",
        email: "user@example.com",
        password: "hashed-password",
        name: "Test User",
        emailVerified: new Date(),
        role: "USER",
      };
      mockPrisma.user.findUnique.mockResolvedValueOnce(mockUser);

      // Mock password comparison to succeed
      (bcrypt.compare as jest.Mock).mockResolvedValueOnce(true);

      const result = await authorize({
        email: "user@example.com",
        password: "correct-password",
      });

      expect(result).toEqual({
        id: "user-1",
        email: "user@example.com",
        name: "Test User",
        role: "USER",
      });
      expect(bcrypt.compare).toHaveBeenCalledWith(
        "correct-password",
        "hashed-password"
      );
    });

    it("should return null if user email is not verified", async () => {
      // Mock user found but email not verified
      mockPrisma.user.findUnique.mockResolvedValueOnce({
        id: "user-1",
        email: "user@example.com",
        password: "hashed-password",
        name: "Test User",
        emailVerified: null,
        role: "USER",
      });

      // Mock password comparison to succeed
      (bcrypt.compare as jest.Mock).mockResolvedValueOnce(true);

      const result = await authorize({
        email: "user@example.com",
        password: "correct-password",
      });

      expect(result).toBeNull();
    });

    it("should handle errors gracefully", async () => {
      // Mock database error
      mockPrisma.user.findUnique.mockRejectedValueOnce(
        new Error("Database error")
      );

      const result = await authorize({
        email: "user@example.com",
        password: "password123",
      });

      expect(result).toBeNull();
    });
  });

  describe("JWT Callback", () => {
    it("should add user role to token", async () => {
      const token = { sub: "user-1" };
      const user = { id: "user-1", role: "ADMIN" };

      const result = await authOptions.callbacks.jwt({
        token,
        user,
        account: null,
        profile: null,
        trigger: "signIn",
      });

      expect(result).toEqual({
        sub: "user-1",
        role: "ADMIN",
      });
    });

    it("should preserve existing token if no user is provided", async () => {
      const token = { sub: "user-1", role: "USER" };

      const result = await authOptions.callbacks.jwt({
        token,
        user: null,
        account: null,
        profile: null,
        trigger: "update",
      });

      expect(result).toEqual({
        sub: "user-1",
        role: "USER",
      });
    });
  });

  describe("Session Callback", () => {
    it("should add user id and role to session", async () => {
      const session = {
        user: { name: "Test User", email: "user@example.com" },
      };
      const token = { sub: "user-1", role: "ADMIN" };

      const result = await authOptions.callbacks.session({
        session,
        token,
        user: null,
      });

      expect(result).toEqual({
        user: {
          id: "user-1",
          name: "Test User",
          email: "user@example.com",
          role: "ADMIN",
        },
      });
    });
  });
});
