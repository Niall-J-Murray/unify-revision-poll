/**
 * Mock implementation of the email service
 * This resolves ESM issues when testing with Jest
 */

const sendVerificationEmail = jest.fn().mockResolvedValue(undefined);
const sendPasswordResetEmail = jest.fn().mockResolvedValue(undefined);

// Export as both CommonJS and mock ESM
module.exports = {
  sendVerificationEmail,
  sendPasswordResetEmail,
  __esModule: true,
};
