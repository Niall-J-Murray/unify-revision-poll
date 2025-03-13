// Mock email service functions
export const sendVerificationEmail = jest.fn().mockResolvedValue(true);
export const sendPasswordResetEmail = jest.fn().mockResolvedValue(true);
export const sendWelcomeEmail = jest.fn().mockResolvedValue(true);

// Helper to reset all mocks
export const resetEmailMocks = () => {
  sendVerificationEmail.mockClear();
  sendPasswordResetEmail.mockClear();
  sendWelcomeEmail.mockClear();
};

// Helper to mock email failure
export const mockEmailFailure = () => {
  sendVerificationEmail.mockRejectedValueOnce(
    new Error("Failed to send email")
  );
  sendPasswordResetEmail.mockRejectedValueOnce(
    new Error("Failed to send email")
  );
  sendWelcomeEmail.mockRejectedValueOnce(new Error("Failed to send email"));
};
