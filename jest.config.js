const nextJest = require("next/jest");

const createJestConfig = nextJest({
  // Provide the path to your Next.js app to load next.config.js and .env files in your test environment
  dir: "./",
});

// Add any custom config to be passed to Jest
const customJestConfig = {
  setupFilesAfterEnv: ["<rootDir>/jest.setup.js"],
  // Use jsdom as the default test environment so component tests work properly
  testEnvironment: "jsdom",
  moduleDirectories: ["node_modules", "<rootDir>"],
  moduleNameMapper: {
    // Handle module aliases (if you use them in the app)
    "^@/(.*)$": "<rootDir>/src/$1",
    // Mock problematic ESM modules
    "^@auth/prisma-adapter$": "<rootDir>/src/__mocks__/prismaAdapter.js",
    // Mock NextAuth route
    "^@/app/api/auth/\\[...nextauth\\]/route$":
      "<rootDir>/src/__mocks__/nextAuthRoute.js",
    // Mock email service
    "^@/lib/email$": "<rootDir>/src/__mocks__/email.js",
    // Mock email-service (if used)
    "^@/lib/email-service$": "<rootDir>/src/__mocks__/email.js",
  },
  collectCoverage: true,
  collectCoverageFrom: [
    "./src/app/api/**/*.ts",
    "./src/app/components/**/*.tsx",
    "./src/lib/**/*.ts",
    "!**/node_modules/**",
    "!**/dist/**",
    "!**/*.d.ts",
    "!**/types/**",
  ],
  coverageThreshold: {
    global: {
      branches: 70,
      functions: 70,
      lines: 70,
      statements: 70,
    },
  },
  transformIgnorePatterns: [
    // This is necessary to make Next.js and other ESM packages work with Jest
    "node_modules/(?!(@auth|next|@next|next-auth|nanoid|jose)/)",
  ],
  testMatch: ["**/__tests__/**/*.test.[jt]s?(x)"],
  transform: {
    "^.+\\.(ts|tsx|js|jsx)$": ["babel-jest", { presets: ["next/babel"] }],
  },
  testEnvironmentOptions: {
    url: "http://localhost:3000",
  },
  watchPlugins: [
    "jest-watch-typeahead/filename",
    "jest-watch-typeahead/testname",
  ],
  // Use different test environments for different types of tests
  projects: [
    {
      displayName: "API",
      testMatch: ["**/__tests__/api/**/*.test.[jt]s?(x)"],
      testEnvironment: "node",
      coverageThreshold: {
        global: {
          branches: 70,
          functions: 70,
          lines: 70,
          statements: 70,
        },
      },
      moduleNameMapper: {
        "^@/(.*)$": "<rootDir>/src/$1",
        "^@auth/prisma-adapter$": "<rootDir>/src/__mocks__/prismaAdapter.js",
        "^@/app/api/auth/\\[...nextauth\\]/route$":
          "<rootDir>/src/__mocks__/nextAuthRoute.js",
        "^@/lib/email$": "<rootDir>/src/__mocks__/email.js",
        "^@/lib/email-service$": "<rootDir>/src/__mocks__/email.js",
      },
      transformIgnorePatterns: [
        "node_modules/(?!(@auth|next|@next|next-auth|nanoid|jose)/)",
      ],
    },
    {
      displayName: "Components",
      testMatch: ["**/__tests__/app/components/**/*.test.[jt]s?(x)"],
      testEnvironment: "jsdom", // Using jsdom for component tests
      setupFilesAfterEnv: ["<rootDir>/jest.setup.js"],
      coverageThreshold: {
        global: {
          branches: 0,
          functions: 0,
          lines: 0,
          statements: 0,
        },
      },
      moduleNameMapper: {
        "^@/(.*)$": "<rootDir>/src/$1",
        "^@auth/prisma-adapter$": "<rootDir>/src/__mocks__/prismaAdapter.js",
        "^@/app/api/auth/\\[...nextauth\\]/route$":
          "<rootDir>/src/__mocks__/nextAuthRoute.js",
        "^@/lib/email$": "<rootDir>/src/__mocks__/email.js",
        "^@/lib/email-service$": "<rootDir>/src/__mocks__/email.js",
      },
      transformIgnorePatterns: [
        "node_modules/(?!(@auth|next|@next|next-auth|nanoid|jose)/)",
      ],
    },
    {
      displayName: "Lib",
      testMatch: ["**/__tests__/lib/**/*.test.[jt]s?(x)"],
      testEnvironment: "node",
      coverageThreshold: {
        global: {
          branches: 70,
          functions: 70,
          lines: 70,
          statements: 70,
        },
      },
      moduleNameMapper: {
        "^@/(.*)$": "<rootDir>/src/$1",
        "^@auth/prisma-adapter$": "<rootDir>/src/__mocks__/prismaAdapter.js",
        "^@/app/api/auth/\\[...nextauth\\]/route$":
          "<rootDir>/src/__mocks__/nextAuthRoute.js",
        "^@/lib/email$": "<rootDir>/src/__mocks__/email.js",
        "^@/lib/email-service$": "<rootDir>/src/__mocks__/email.js",
      },
      transformIgnorePatterns: [
        "node_modules/(?!(@auth|next|@next|next-auth|nanoid|jose)/)",
      ],
    },
  ],
};

// createJestConfig is exported this way to ensure that next/jest can load the Next.js config which is async
module.exports = createJestConfig(customJestConfig);
