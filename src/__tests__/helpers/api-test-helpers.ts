import { NextRequest } from "next/server";
import { getServerSession } from "next-auth/next";

/**
 * Creates a mock NextRequest with the given options
 */
/**
 * Creates a mock HTTP request object for testing purposes.
 * Allows customization of method, URL, headers, body, and search parameters.
 * Returns a NextRequest object with the specified options.
 *
 * @param options - Configuration options for the mock request.
 * @param options.method - The HTTP method (default is "GET").
 * @param options.url - The request URL (default is "http://localhost:3000/api/test").
 * @param options.headers - An object representing request headers.
 * @param options.body - The request body, can be any type.
 * @param options.searchParams - An object representing URL search parameters.
 * @returns A mock NextRequest object.
 * @throws Throws a TypeError if the URL is invalid.
 */
/**
 * Creates a mock HTTP request object for testing purposes, allowing customization of various request options.
 * This function is useful for simulating HTTP requests in unit tests.
 *
 * @param options - Configuration options for the mock request.
 * @param options.method - The HTTP method (default is "GET").
 * @param options.url - The request URL (default is "http://localhost:3000/api/test").
 * @param options.headers - An object representing request headers.
 * @param options.body - The request body, can be any type.
 * @param options.searchParams - An object representing URL search parameters.
 * @returns A mock NextRequest object.
 * @throws Throws a TypeError if the URL is invalid.
 */
export function createMockRequest(options: {
  method?: string;
  url?: string;
  headers?: Record<string, string>;
  body?: any;
  searchParams?: Record<string, string>;
}) {
  const {
    method = "GET",
    url = "http://localhost:3000/api/test",
    headers = {},
    body = null,
    searchParams = {},
  } = options;

  // Create URL with search params
  const urlObj = new URL(url);
  Object.entries(searchParams).forEach(([key, value]) => {
    urlObj.searchParams.set(key, value);
  });

  // Create headers
  const headersObj = new Headers();
  Object.entries(headers).forEach(([key, value]) => {
    headersObj.set(key, value);
  });

  // Create a mock request object instead of using NextRequest constructor
  const req = {
    method,
    url: urlObj.toString(),
    headers: headersObj,
    nextUrl: urlObj,
    json: jest.fn().mockResolvedValue(body),
  };

  return req;
}

// Create an alias for compatibility with existing tests
export const createMockNextRequest = createMockRequest;

/**
 * Creates a mock authenticated session
 */
/**
 * Mocks an authenticated session for testing purposes by providing a mock user object.
 *
 * @param role - The role of the user, either "USER" or "ADMIN". Defaults to "USER".
 * @returns void
 * @throws None
 */
export function mockAuthenticatedSession(role: "USER" | "ADMIN" = "USER") {
  (getServerSession as jest.Mock).mockResolvedValue({
    user: {
      id: "mock-user-id",
      name: "Test User",
      email: "test@example.com",
      role,
    },
  });
}

/**
 * Creates a mock unauthenticated session (null)
 */
/**
 * Mocks an unauthenticated session by resolving the server session to null.
 * This is useful for testing scenarios where user authentication is not required.
 *
 * @returns {void} - This function does not return a value.
 * @throws {void} - This function does not throw exceptions.
 */
/**
 * Mocks an unauthenticated session by resolving the server session to null.
 * This is useful for testing scenarios where user authentication is not required.
 *
 * @returns {void} - This function does not return a value.
 * @throws {void} - This function does not throw exceptions.
 */
export function mockUnauthenticatedSession() {
  (getServerSession as jest.Mock).mockResolvedValue(null);
}

/**
 * Asserts that the response has the expected status and data
 */
/**
 * Asserts that the response status matches the expected status and optionally checks the response data.
 *
 * @param response - The response object to be validated.
 * @param expectedStatus - The expected HTTP status code.
 * @param expectedData - Optional expected data to compare against the response JSON.
 * @returns A promise that resolves when the assertions are complete.
 * @throws Will throw an error if the status or data does not match the expectations.
 */
export function assertResponse(
  response: any,
  expectedStatus: number,
  expectedData?: any
) {
  expect(response.status).toBe(expectedStatus);

  if (expectedData) {
    return response.json().then((data: any) => {
      expect(data).toEqual(expectedData);
    });
  }
}

/**
 * Runs a test for an API endpoint with common setup
 */
/**
 * Tests an API endpoint by simulating a request and asserting the response.
 * It allows configuration of request method, authentication, user role, and expected outcomes.
 *
 * @param description - A brief description of the test case.
 * @param handler - The function that handles the API request.
 * @param options - Configuration options for the test, including method, authentication, role, request options, expected status, expected data, and a setup function.
 * @returns void
 * @throws Error if the response status or data does not match the expected values.
 */
export function testApiEndpoint(
  description: string,
  handler: Function,
  options: {
    method?: "GET" | "POST" | "PUT" | "DELETE" | "PATCH";
    authenticated?: boolean;
    role?: "USER" | "ADMIN";
    requestOptions?: Parameters<typeof createMockRequest>[0];
    expectedStatus: number;
    expectedData?: any;
    beforeTest?: () => void;
  }
) {
  const {
    method = "GET",
    authenticated = true,
    role = "USER",
    requestOptions = {},
    expectedStatus,
    expectedData,
    beforeTest,
  } = options;

  it(description, async () => {
    // Setup authentication
    if (authenticated) {
      mockAuthenticatedSession(role);
    } else {
      mockUnauthenticatedSession();
    }

    // Run any additional setup
    if (beforeTest) {
      beforeTest();
    }

    // Create request
    const req = createMockRequest({
      method,
      ...requestOptions,
    });

    // Call handler
    const response = await handler(req);

    // Assert response
    await assertResponse(response, expectedStatus, expectedData);
  });
}
