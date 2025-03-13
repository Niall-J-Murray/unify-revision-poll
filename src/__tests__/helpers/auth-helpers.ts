/**
 * Helper functions for mocking authentication in tests
 */

export function createMockUnauthSession() {
  return null;
}

export function createMockAuthSession(user: any) {
  return {
    user,
    expires: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
  };
}

export function createMockAdminSession(overrides: any = {}) {
  const user = {
    id: "admin-123",
    name: "Admin User",
    email: "admin@example.com",
    role: "admin",
    ...overrides,
  };

  return createMockAuthSession(user);
}
