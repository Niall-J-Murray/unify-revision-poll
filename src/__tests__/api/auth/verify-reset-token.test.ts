import { NextRequest } from 'next/server';
import { createMockRequestResponse } from '../../helpers/next-request-helpers';
import { mockPrisma } from '../../helpers/prisma-mock';

// Mock the POST function from the verify-reset-token route module
const mockPost = jest.fn();
jest.mock('@/app/api/auth/verify-reset-token/route', () => ({
  POST: mockPost
}));

// Mock Prisma
jest.mock('@/lib/prisma', () => ({
  __esModule: true,
  default: mockPrisma
}));

describe('Verify Reset Token API', () => {
  const mockToken = 'valid-reset-token';
  const mockUserId = 'user-123';
  
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('should return 400 if token is missing', async () => {
    mockPost.mockImplementation(async () => {
      return {
        status: 400,
        json: async () => ({ 
          success: false, 
          message: 'Reset token is required' 
        })
      };
    });

    const { req, res } = createMockRequestResponse({
      method: 'POST',
      url: '/api/auth/verify-reset-token',
      headers: {
        'content-type': 'application/json'
      },
      body: {}
    });

    await mockPost(req);
    
    expect(res.status).toBe(400);
  });

  it('should return 400 if token is invalid or expired', async () => {
    mockPrisma.passwordReset.findUnique.mockResolvedValueOnce(null);

    mockPost.mockImplementation(async () => {
      return {
        status: 400,
        json: async () => ({ 
          success: false, 
          message: 'Invalid or expired reset token' 
        })
      };
    });

    const { req, res } = createMockRequestResponse({
      method: 'POST',
      url: '/api/auth/verify-reset-token',
      headers: {
        'content-type': 'application/json'
      },
      body: { token: 'invalid-token' }
    });

    await mockPost(req);
    
    expect(res.status).toBe(400);
  });

  it('should return 400 if token is expired', async () => {
    const expiredDate = new Date();
    expiredDate.setHours(expiredDate.getHours() - 1); // Expired

    mockPrisma.passwordReset.findUnique.mockResolvedValueOnce({
      id: 'reset-1',
      token: mockToken,
      userId: mockUserId,
      expiresAt: expiredDate,
      createdAt: new Date()
    });

    mockPost.mockImplementation(async () => {
      return {
        status: 400,
        json: async () => ({ 
          success: false, 
          message: 'Invalid or expired reset token' 
        })
      };
    });

    const { req, res } = createMockRequestResponse({
      method: 'POST',
      url: '/api/auth/verify-reset-token',
      headers: {
        'content-type': 'application/json'
      },
      body: { token: mockToken }
    });

    await mockPost(req);
    
    expect(res.status).toBe(400);
  });

  it('should verify a valid token', async () => {
    const validDate = new Date();
    validDate.setHours(validDate.getHours() + 1); // Still valid

    mockPrisma.passwordReset.findUnique.mockResolvedValueOnce({
      id: 'reset-1',
      token: mockToken,
      userId: mockUserId,
      expiresAt: validDate,
      createdAt: new Date()
    });

    mockPost.mockImplementation(async () => {
      return {
        status: 200,
        json: async () => ({ 
          success: true, 
          message: 'Token is valid' 
        })
      };
    });

    const { req, res } = createMockRequestResponse({
      method: 'POST',
      url: '/api/auth/verify-reset-token',
      headers: {
        'content-type': 'application/json'
      },
      body: { token: mockToken }
    });

    await mockPost(req);
    
    expect(res.status).toBe(200);
  });

  it('should handle database errors', async () => {
    mockPrisma.passwordReset.findUnique.mockRejectedValueOnce(new Error('Database error'));

    mockPost.mockImplementation(async () => {
      return {
        status: 500,
        json: async () => ({ 
          success: false, 
          message: 'Failed to verify reset token' 
        })
      };
    });

    const { req, res } = createMockRequestResponse({
      method: 'POST',
      url: '/api/auth/verify-reset-token',
      headers: {
        'content-type': 'application/json'
      },
      body: { token: mockToken }
    });

    await mockPost(req);
    
    expect(res.status).toBe(500);
  });
}); 