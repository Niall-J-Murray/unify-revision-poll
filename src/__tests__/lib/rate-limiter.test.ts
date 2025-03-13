import { checkLoginRateLimit, resetLoginAttempts } from "@/lib/rate-limiter";

jest.mock("next/server", () => ({
  NextResponse: {
    json: jest.fn((data) => ({ data })),
  },
}));

describe("Rate Limiter", () => {
  // Store original Date.now
  const originalDateNow = Date.now;
  let currentTime = Date.now();

  beforeEach(() => {
    // Mock Date.now to control time
    Date.now = jest.fn(() => currentTime);

    // Reset all login attempts before each test
    resetLoginAttempts("test@example.com");
    resetLoginAttempts("another@example.com");
  });

  afterEach(() => {
    // Restore original Date.now
    Date.now = originalDateNow;
  });

  it("should allow first login attempt and return correct remaining attempts", () => {
    const result = checkLoginRateLimit("test@example.com");

    expect(result.success).toBe(true);
    expect(result.remainingAttempts).toBe(4); // 5 max attempts - 1 current attempt = 4 remaining
    expect(result.resetTime).toBeInstanceOf(Date);
  });

  it("should track multiple login attempts and return correct remaining attempts", () => {
    // First attempt
    checkLoginRateLimit("test@example.com");

    // Second attempt
    const result = checkLoginRateLimit("test@example.com");

    expect(result.success).toBe(true);
    expect(result.remainingAttempts).toBe(3); // 5 max attempts - 2 current attempts = 3 remaining
  });

  it("should block further attempts after max attempts are reached", () => {
    // Make 5 attempts (max allowed)
    for (let i = 0; i < 5; i++) {
      checkLoginRateLimit("test@example.com");
    }

    // 6th attempt should be blocked
    const result = checkLoginRateLimit("test@example.com");

    expect(result.success).toBe(false);
    expect(result.remainingAttempts).toBeUndefined(); // No remaining attempts when blocked
    expect(result.message).toContain("Too many login attempts");
  });

  it("should reset attempts counter when resetLoginAttempts is called", () => {
    // Make 3 attempts
    for (let i = 0; i < 3; i++) {
      checkLoginRateLimit("test@example.com");
    }

    // Reset attempts
    resetLoginAttempts("test@example.com");

    // Next attempt should be treated as first attempt
    const result = checkLoginRateLimit("test@example.com");

    expect(result.success).toBe(true);
    expect(result.remainingAttempts).toBe(4); // 5 max attempts - 1 current attempt = 4 remaining
  });

  it("should reset attempts counter after time window expires", () => {
    // Make 3 attempts
    for (let i = 0; i < 3; i++) {
      checkLoginRateLimit("test@example.com");
    }

    // Advance time by 16 minutes (past the 15 minute window)
    currentTime += 16 * 60 * 1000;

    // Next attempt should be treated as first attempt
    const result = checkLoginRateLimit("test@example.com");

    expect(result.success).toBe(true);
    expect(result.remainingAttempts).toBe(4); // 5 max attempts - 1 current attempt = 4 remaining
  });

  it("should track different identifiers separately", () => {
    // Make 5 attempts for first user (max allowed)
    for (let i = 0; i < 5; i++) {
      checkLoginRateLimit("test@example.com");
    }

    // First attempt for second user should be allowed
    const result = checkLoginRateLimit("another@example.com");

    expect(result.success).toBe(true);
    expect(result.remainingAttempts).toBe(4); // 5 max attempts - 1 current attempt = 4 remaining
  });
});
