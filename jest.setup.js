// Import jest-dom for DOM matchers
require("@testing-library/jest-dom");

// Set up a minimal fetch polyfill for Node environment
global.fetch = jest.fn(() =>
  Promise.resolve({
    ok: true,
    json: () => Promise.resolve({}),
  })
);

// Add window.URL.createObjectURL mock for testing file uploads/downloads
if (typeof window !== "undefined") {
  window.URL.createObjectURL = jest.fn(() => "mock-url");
  window.URL.revokeObjectURL = jest.fn();
}

// Mock the Next.js router
jest.mock("next/navigation", () => ({
  useRouter: () => ({
    push: jest.fn(),
    replace: jest.fn(),
    prefetch: jest.fn(),
    back: jest.fn(),
    forward: jest.fn(),
    refresh: jest.fn(),
    pathname: "/",
    query: {},
  }),
  usePathname: () => "/",
  useSearchParams: () => ({
    get: jest.fn(),
    getAll: jest.fn(),
    toString: jest.fn(),
  }),
}));

// Mock next-auth
jest.mock("next-auth/react", () => {
  return {
    signIn: jest.fn(),
    signOut: jest.fn(),
    useSession: jest.fn(() => {
      return {
        data: {
          user: {
            id: "mock-user-id",
            name: "Test User",
            email: "test@example.com",
            role: "USER",
          },
        },
        status: "authenticated",
      };
    }),
  };
});

// Mock server session
jest.mock("next-auth/next", () => ({
  getServerSession: jest.fn(() => ({
    user: {
      id: "mock-user-id",
      name: "Test User",
      email: "test@example.com",
      role: "USER",
    },
  })),
}));

// Fix for missing globals in test environment
// These are only needed for node environment tests
if (typeof window === "undefined") {
  global.Request = class Request {};
  global.Response = class Response {};
  global.Headers = class Headers {};
}

// Some DOM mocks for component testing
if (typeof window !== "undefined") {
  // Mock IntersectionObserver
  class MockIntersectionObserver {
    constructor(callback) {
      this.callback = callback;
    }
    observe() {
      return null;
    }
    unobserve() {
      return null;
    }
    disconnect() {
      return null;
    }
  }
  window.IntersectionObserver = MockIntersectionObserver;

  // Mock ResizeObserver
  class MockResizeObserver {
    constructor(callback) {
      this.callback = callback;
    }
    observe() {
      return null;
    }
    unobserve() {
      return null;
    }
    disconnect() {
      return null;
    }
  }
  window.ResizeObserver = MockResizeObserver;
}

// Mock NextResponse for App Router API endpoints
jest.mock("next/server", () => {
  const originalModule = jest.requireActual("next/server");
  return {
    ...originalModule,
    NextResponse: {
      json: jest.fn((data, options = {}) => ({
        json: async () => data,
        status: options.status || 200,
        headers: new Map(),
      })),
    },
  };
});

// Mock @auth/prisma-adapter module to avoid ESM issues
jest.mock("@auth/prisma-adapter", () => ({
  PrismaAdapter: jest.fn((prisma) => {
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
      createVerificationToken: jest.fn(),
      useVerificationToken: jest.fn(),
      deleteUser: jest.fn(),
      unlinkAccount: jest.fn(),
    };
  }),
}));

// Mock NextAuth itself
jest.mock("next-auth", () => ({
  __esModule: true,
  default: jest.fn(() => ({
    GET: jest.fn(),
    POST: jest.fn(),
  })),
}));
