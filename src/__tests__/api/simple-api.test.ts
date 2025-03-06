import { mockPrisma } from '../helpers/prisma-mock';

// Mock a simple API route
const mockApiHandler = jest.fn();

// Mock Prisma
jest.mock('@/lib/prisma', () => ({
  __esModule: true,
  default: mockPrisma
}));

describe('Simple API Test', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('should mock a simple API response', async () => {
    // Create a mock response object
    const mockResponse = {
      status: 200,
      json: jest.fn().mockResolvedValue({ message: 'Success' })
    };
    
    // Set up the mock to return our response
    mockApiHandler.mockResolvedValueOnce(mockResponse);
    
    // Call the mock API handler
    const result = await mockApiHandler();
    
    // Verify the response
    expect(result.status).toBe(200);
    const data = await result.json();
    expect(data).toEqual({ message: 'Success' });
  });

  it('should handle error responses', async () => {
    // Create a mock error response
    const mockResponse = {
      status: 404,
      json: jest.fn().mockResolvedValue({ message: 'Not Found' })
    };
    
    // Set up the mock to return our response
    mockApiHandler.mockResolvedValueOnce(mockResponse);
    
    // Call the mock API handler
    const result = await mockApiHandler();
    
    // Verify the response
    expect(result.status).toBe(404);
    const data = await result.json();
    expect(data).toEqual({ message: 'Not Found' });
  });

  it('should interact with mocked Prisma', async () => {
    // Mock Prisma to return specific data
    mockPrisma.user.findUnique.mockResolvedValueOnce({
      id: 'test-user',
      name: 'Test User',
      email: 'test@example.com'
    });
    
    // Create a mock response
    const mockResponse = {
      status: 200,
      json: jest.fn().mockResolvedValue({ user: { id: 'test-user' } })
    };
    
    // Set up the mock to return our response
    mockApiHandler.mockImplementationOnce(async () => {
      // Actually call the Prisma mock
      const user = await mockPrisma.user.findUnique({ where: { id: 'test-user' } });
      return mockResponse;
    });
    
    // Call the mock API handler
    const result = await mockApiHandler();
    
    // Verify the response
    expect(result.status).toBe(200);
    const data = await result.json();
    expect(data).toEqual({ user: { id: 'test-user' } });
    
    // Verify Prisma was called
    expect(mockPrisma.user.findUnique).toHaveBeenCalledTimes(1);
    expect(mockPrisma.user.findUnique).toHaveBeenCalledWith({ where: { id: 'test-user' } });
  });
}); 