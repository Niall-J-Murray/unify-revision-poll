import { NextRequest } from 'next/server';

// Mock implementation of NextRequest with only what we need for tests
export function createMockNextRequest(options: {
  method?: string;
  url?: string;
  headers?: Record<string, string>;
  body?: any;
}) {
  const { method = 'GET', url = 'http://localhost:3000', headers = {}, body = null } = options;

  // Parse URL to get searchParams - make sure it's a full URL
  const fullUrl = url.startsWith('http') ? url : `http://localhost:3000${url.startsWith('/') ? '' : '/'}${url}`;
  const urlObj = new URL(fullUrl);
  
  // Create a mock NextRequest
  const mockNextRequest = {
    method,
    headers: new Headers(headers),
    nextUrl: {
      pathname: urlObj.pathname,
      searchParams: urlObj.searchParams,
    },
    json: jest.fn().mockResolvedValue(body),
  };

  return mockNextRequest;
}

export function createJsonResponse(data: any, status = 200) {
  return {
    json: jest.fn().mockReturnValue(data),
    status,
  };
}

// Function to create both a mock request and response for easier testing
export function createMockRequestResponse(options: {
  method?: string;
  url?: string;
  headers?: Record<string, string>;
  body?: any;
}) {
  const req = createMockNextRequest(options);
  
  // Create a mock response object with status and json methods
  const res = {
    statusCode: 200, // Default status
    json: jest.fn().mockImplementation((data) => {
      return {
        status: res.statusCode,
        json: jest.fn().mockResolvedValue(data)
      };
    }),
    // Method to set status, chainable like res.status(404).json(...)
    status: jest.fn().mockImplementation((statusCode) => {
      res.statusCode = statusCode;
      return res;
    })
  };

  return { req, res };
} 