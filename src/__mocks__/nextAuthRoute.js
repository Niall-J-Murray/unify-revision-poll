/**
 * Mock implementation of the NextAuth route
 * This resolves ESM issues when testing with Jest
 */
const { PrismaAdapter } = require("@auth/prisma-adapter");
const { mockPrisma } = require("../helpers/prisma-mock");
const bcrypt = require("bcryptjs");

// Create the adapter with mockPrisma
const adapter = PrismaAdapter(mockPrisma);

// Mock the credentials provider authorize function
const credentialsAuthorize = jest
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

      const isValid = await bcrypt.compare(credentials.password, user.password);

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

// Mock JWT callback
const jwtCallback = jest.fn().mockImplementation(({ token, user }) => {
  if (user) {
    // Add both id and role to token
    token.id = user.id;
    token.role = user.role;
  }
  return token;
});

// Mock session callback
const sessionCallback = jest.fn().mockImplementation(({ session, token }) => {
  if (session.user) {
    session.user.id = token.sub || token.id;
    session.user.role = token.role;
  }
  return session;
});

const authOptions = {
  adapter: adapter,
  providers: [
    {
      id: "credentials",
      name: "Credentials",
      credentials: {
        email: { label: "Email", type: "email" },
        password: { label: "Password", type: "password" },
      },
      authorize: credentialsAuthorize,
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
    redirect: ({ url, baseUrl }) => {
      return baseUrl;
    },
  },
  pages: {
    signIn: "/login",
    error: "/login",
  },
  secret: "test-secret",
};

const handlers = {
  GET: jest.fn(),
  POST: jest.fn(),
};

// Export as both CommonJS and mock ESM
module.exports = {
  authOptions,
  GET: handlers.GET,
  POST: handlers.POST,
  credentialsAuthorize,
  jwtCallback,
  sessionCallback,
  __esModule: true,
  default: handlers,
};
