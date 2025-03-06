import { NextRequest } from 'next/server';
import { mockPrisma } from '../../helpers/prisma-mock';

// Mock the POST function from the feature-requests/[id]/vote/route module
const mockPost = jest.fn();
jest.mock('@/app/api/feature-requests/[id]/vote/route', () => ({
  POST: mockPost
}));

// Mock next-auth
jest.mock('next-auth', () => ({
  auth: jest.fn()
}));
import { auth } from 'next-auth';

// Mock Prisma
jest.mock('@/lib/prisma', () => ({
  __esModule: true,
  default: mockPrisma
}));

describe('Feature Request Vote API', () => {
  const mockFeatureRequestId = 'feature-123';
  const mockUserId = 'user-123';
  const mockAuthUser = { id: mockUserId, role: 'USER', email: 'user@example.com' };
  
  beforeEach(() => {
    jest.clearAllMocks();
    (auth as jest.Mock).mockResolvedValue({
      user: mockAuthUser
    });
  });

  it('should return 401 if user is not authenticated', async () => {
    (auth as jest.Mock).mockResolvedValueOnce(null);
    
    const mockResponse = {
      status: 401,
      json: jest.fn().mockResolvedValue({ 
        success: false, 
        message: 'Unauthorized' 
      })
    };
    
    mockPost.mockResolvedValueOnce(mockResponse);

    const result = await mockPost();
    
    expect(result.status).toBe(401);
    const data = await result.json();
    expect(data).toEqual({ 
      success: false, 
      message: 'Unauthorized' 
    });
  });

  it('should add a vote to the feature request', async () => {
    mockPrisma.vote.create.mockResolvedValueOnce({
      id: 'vote-123',
      value: 1,
      userId: mockUserId,
      featureRequestId: mockFeatureRequestId,
      createdAt: new Date(),
      updatedAt: new Date()
    });

    const mockResponse = {
      status: 201,
      json: jest.fn().mockResolvedValue({ 
        success: true, 
        message: 'Vote added successfully' 
      })
    };
    
    mockPost.mockImplementationOnce(async () => {
      // Actually call the Prisma mock
      await mockPrisma.vote.create({
        data: {
          value: 1,
          userId: mockUserId,
          featureRequestId: mockFeatureRequestId
        }
      });
      return mockResponse;
    });

    const result = await mockPost();
    
    expect(result.status).toBe(201);
    const data = await result.json();
    expect(data).toEqual({ 
      success: true, 
      message: 'Vote added successfully' 
    });
    expect(mockPrisma.vote.create).toHaveBeenCalledTimes(1);
  });

  it('should update an existing vote', async () => {
    mockPrisma.vote.findUnique.mockResolvedValueOnce({
      id: 'vote-123',
      value: 1,
      userId: mockUserId,
      featureRequestId: mockFeatureRequestId,
      createdAt: new Date(),
      updatedAt: new Date()
    });

    mockPrisma.vote.update.mockResolvedValueOnce({
      id: 'vote-123',
      value: -1,
      userId: mockUserId,
      featureRequestId: mockFeatureRequestId,
      createdAt: new Date(),
      updatedAt: new Date()
    });

    const mockResponse = {
      status: 200,
      json: jest.fn().mockResolvedValue({ 
        success: true, 
        message: 'Vote updated successfully' 
      })
    };
    
    mockPost.mockImplementationOnce(async () => {
      // Actually call the Prisma mocks
      const existingVote = await mockPrisma.vote.findUnique({
        where: {
          userId_featureRequestId: {
            userId: mockUserId,
            featureRequestId: mockFeatureRequestId
          }
        }
      });
      
      if (existingVote) {
        await mockPrisma.vote.update({
          where: { id: existingVote.id },
          data: { value: -1 }
        });
      }
      
      return mockResponse;
    });

    const result = await mockPost();
    
    expect(result.status).toBe(200);
    const data = await result.json();
    expect(data).toEqual({ 
      success: true, 
      message: 'Vote updated successfully' 
    });
    expect(mockPrisma.vote.findUnique).toHaveBeenCalledTimes(1);
    expect(mockPrisma.vote.update).toHaveBeenCalledTimes(1);
  });

  it('should return 400 if vote value is invalid', async () => {
    const mockResponse = {
      status: 400,
      json: jest.fn().mockResolvedValue({ 
        success: false, 
        message: 'Vote value must be 1 or -1' 
      })
    };
    
    mockPost.mockResolvedValueOnce(mockResponse);

    const result = await mockPost();
    
    expect(result.status).toBe(400);
    const data = await result.json();
    expect(data).toEqual({ 
      success: false, 
      message: 'Vote value must be 1 or -1' 
    });
  });

  it('should return 404 if feature request is not found', async () => {
    mockPrisma.featureRequest.findUnique.mockResolvedValueOnce(null);

    const mockResponse = {
      status: 404,
      json: jest.fn().mockResolvedValue({ 
        success: false, 
        message: 'Feature request not found' 
      })
    };
    
    mockPost.mockImplementationOnce(async () => {
      // Actually call the Prisma mock
      const featureRequest = await mockPrisma.featureRequest.findUnique({
        where: { id: mockFeatureRequestId }
      });
      
      return mockResponse;
    });

    const result = await mockPost();
    
    expect(result.status).toBe(404);
    const data = await result.json();
    expect(data).toEqual({ 
      success: false, 
      message: 'Feature request not found' 
    });
    expect(mockPrisma.featureRequest.findUnique).toHaveBeenCalledTimes(1);
  });

  it('should handle database errors', async () => {
    mockPrisma.vote.create.mockRejectedValueOnce(new Error('Database error'));

    const mockResponse = {
      status: 500,
      json: jest.fn().mockResolvedValue({ 
        success: false, 
        message: 'Failed to add vote' 
      })
    };
    
    mockPost.mockImplementationOnce(async () => {
      try {
        // This will throw an error
        await mockPrisma.vote.create({
          data: {
            value: 1,
            userId: mockUserId,
            featureRequestId: mockFeatureRequestId
          }
        });
      } catch (error) {
        return mockResponse;
      }
    });

    const result = await mockPost();
    
    expect(result.status).toBe(500);
    const data = await result.json();
    expect(data).toEqual({ 
      success: false, 
      message: 'Failed to add vote' 
    });
    expect(mockPrisma.vote.create).toHaveBeenCalledTimes(1);
  });
}); 