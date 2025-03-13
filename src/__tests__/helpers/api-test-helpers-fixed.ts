import { NextRequest } from "next/server";

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
 * @param options.jsonError - Error to be thrown when json() is called
 * @returns A mock NextRequest object.
 * @throws Throws a TypeError if the URL is invalid.
 */
export function createMockRequest(options: {
  method?: string;
  url?: string;
  headers?: Record<string, string>;
  body?: any;
  searchParams?: Record<string, string>;
  jsonError?: Error;
}) {
  const {
    method = "GET",
    url = "http://localhost:3000/api/test",
    headers = {},
    body = null,
    searchParams = {},
    jsonError = null,
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
    json: jsonError
      ? jest.fn().mockRejectedValue(jsonError)
      : jest.fn().mockResolvedValue(body),
  };

  return req;
}

/**
 * Asserts that the response has the expected status and data
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
