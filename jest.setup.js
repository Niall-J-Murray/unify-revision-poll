// Import jest-dom for DOM matchers
require('@testing-library/jest-dom');

// Set up a minimal fetch polyfill for Node environment
global.fetch = jest.fn(() =>
  Promise.resolve({
    ok: true,
    json: () => Promise.resolve({}),
  })
);

// Mock the Next.js router
jest.mock('next/navigation', () => ({
  useRouter: () => ({
    push: jest.fn(),
    replace: jest.fn(),
    prefetch: jest.fn(),
    back: jest.fn(),
    forward: jest.fn(),
    refresh: jest.fn(),
    pathname: '/',
    query: {},
  }),
  usePathname: () => '/',
  useSearchParams: () => ({
    get: jest.fn(),
    getAll: jest.fn(),
    toString: jest.fn(),
  }),
}));

// Mock next-auth
jest.mock('next-auth/react', () => {
  return {
    signIn: jest.fn(),
    signOut: jest.fn(),
    useSession: jest.fn(() => {
      return {
        data: {
          user: {
            id: 'mock-user-id',
            name: 'Test User',
            email: 'test@example.com',
            role: 'USER',
          },
        },
        status: 'authenticated',
      };
    }),
  };
});

// Mock server session
jest.mock('next-auth/next', () => ({
  getServerSession: jest.fn(() => ({
    user: {
      id: 'mock-user-id',
      name: 'Test User',
      email: 'test@example.com',
      role: 'USER',
    },
  })),
}));

// Fix for missing globals in test environment
global.Request = class Request {};
global.Response = class Response {};
global.Headers = class Headers {};

// Mock NextResponse for App Router API endpoints
jest.mock('next/server', () => {
  const originalModule = jest.requireActual('next/server');
  return {
    ...originalModule,
    NextResponse: {
      json: jest.fn((data, options = {}) => ({
        json: async () => data,
        status: options.status || 200,
      })),
    },
  };
});

// Mock @auth/prisma-adapter module to avoid ESM issues
jest.mock('@auth/prisma-adapter', () => ({
  PrismaAdapter: jest.fn().mockReturnValue({
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
  }),
}));

// Mock NextAuth itself
jest.mock('next-auth', () => ({
  __esModule: true,
  default: jest.fn(() => ({
    GET: jest.fn(),
    POST: jest.fn(),
  })),
})); 