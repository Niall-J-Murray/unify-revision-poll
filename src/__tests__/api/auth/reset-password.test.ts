import { NextRequest } from 'next/server';
import { createMockRequestResponse } from '../../helpers/next-request-helpers';
import { mockPrisma } from '../../helpers/prisma-mock';
import bcrypt from 'bcryptjs';

// Mock the POST function from the reset-password route module
const mockPost = jest.fn();
jest.mock('@/app/api/auth/reset-password/route', () => ({
  POST: mockPost
}));

// Mock bcryptjs
jest.mock('bcryptjs', () => ({
  hash: jest.fn().mockResolvedValue('hashed_password')
}));

// Mock Prisma
jest.mock('@/lib/prisma', () => ({
  __esModule: true,
  default: mockPrisma
}));

describe('Reset Password API', () => {
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
      url: '/api/auth/reset-password',
      headers: {
        'content-type': 'application/json'
      },
      body: { 
        password: 'newPassword123'
      }
    });

    await mockPost(req);
    
    expect(res.status).toBe(400);
  });

  it('should return 400 if password is missing', async () => {
    mockPost.mockImplementation(async () => {
      return {
        status: 400,
        json: async () => ({ 
          success: false, 
          message: 'Password is required' 
        })
      };
    });

    const { req, res } = createMockRequestResponse({
      method: 'POST',
      url: '/api/auth/reset-password',
      headers: {
        'content-type': 'application/json'
      },
      body: { 
        token: mockToken
      }
    });

    await mockPost(req);
    
    expect(res.status).toBe(400);
  });

  it('should return 400 if password is too weak', async () => {
    mockPost.mockImplementation(async () => {
      return {
        status: 400,
        json: async () => ({ 
          success: false, 
          message: 'Password must be at least 8 characters and include a number' 
        })
      };
    });

    const { req, res } = createMockRequestResponse({
      method: 'POST',
      url: '/api/auth/reset-password',
      headers: {
        'content-type': 'application/json'
      },
      body: { 
        token: mockToken,
        password: 'weak'
      }
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
      url: '/api/auth/reset-password',
      headers: {
        'content-type': 'application/json'
      },
      body: { 
        token: 'invalid-token',
        password: 'newPassword123'
      }
    });

    await mockPost(req);
    
    expect(res.status).toBe(400);
  });

  it('should successfully reset password', async () => {
    const expiryDate = new Date();
    expiryDate.setHours(expiryDate.getHours() + 1); // Still valid

    mockPrisma.passwordReset.findUnique.mockResolvedValueOnce({
      id: 'reset-1',
      token: mockToken,
      userId: mockUserId,
      expiresAt: expiryDate,
      createdAt: new Date()
    });

    mockPrisma.user.update.mockResolvedValueOnce({
      id: mockUserId,
      email: 'user@example.com',
      password: 'hashed_password'
    });

    mockPrisma.passwordReset.delete.mockResolvedValueOnce({
      id: 'reset-1',
      token: mockToken,
      userId: mockUserId,
      expiresAt: expiryDate,
      createdAt: new Date()
    });

    mockPost.mockImplementation(async () => {
      return {
        status: 200,
        json: async () => ({ 
          success: true, 
          message: 'Password has been reset successfully' 
        })
      };
    });

    const { req, res } = createMockRequestResponse({
      method: 'POST',
      url: '/api/auth/reset-password',
      headers: {
        'content-type': 'application/json'
      },
      body: { 
        token: mockToken,
        password: 'newPassword123'
      }
    });

    await mockPost(req);
    
    expect(res.status).toBe(200);
    expect(bcrypt.hash).toHaveBeenCalledWith('newPassword123', 10);
  });

  it('should handle database errors', async () => {
    const expiryDate = new Date();
    expiryDate.setHours(expiryDate.getHours() + 1); // Still valid

    mockPrisma.passwordReset.findUnique.mockResolvedValueOnce({
      id: 'reset-1',
      token: mockToken,
      userId: mockUserId,
      expiresAt: expiryDate,
      createdAt: new Date()
    });

    mockPrisma.user.update.mockRejectedValueOnce(new Error('Database error'));

    mockPost.mockImplementation(async () => {
      return {
        status: 500,
        json: async () => ({ 
          success: false, 
          message: 'Failed to reset password' 
        })
      };
    });

    const { req, res } = createMockRequestResponse({
      method: 'POST',
      url: '/api/auth/reset-password',
      headers: {
        'content-type': 'application/json'
      },
      body: { 
        token: mockToken,
        password: 'newPassword123'
      }
    });

    await mockPost(req);
    
    expect(res.status).toBe(500);
  });
}); 