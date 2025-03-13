/**
 * Mock implementation of @auth/prisma-adapter
 * This resolves ESM issues when testing with Jest
 */

const PrismaAdapter = jest.fn().mockImplementation((prisma) => {
  return {
    createUser: jest.fn(),
    getUser: jest.fn(),
    getUserByEmail: jest.fn(),
    getUserByAccount: jest.fn(),
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
  };
});

// Export as both CommonJS and mock ESM
module.exports = {
  PrismaAdapter,
  default: PrismaAdapter,
  __esModule: true,
};
