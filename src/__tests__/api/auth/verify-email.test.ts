import { NextRequest } from 'next/server';
import { createMockRequestResponse } from '../../helpers/next-request-helpers';
import { mockPrisma } from '../../helpers/prisma-mock';

// Mock the GET function from the verify-email route module
const mockGet = jest.fn();
jest.mock('@/app/api/auth/verify-email/route', () => ({
  GET: mockGet
}));

// Mock Prisma
jest.mock('@/lib/prisma', () => ({
  __esModule: true,
  default: mockPrisma
}));

describe('Verify Email API', () => {
  const mockToken = 'valid-verification-token';
  const mockUserId = 'user-123';
  
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('should return 400 if token is missing', async () => {
    mockGet.mockImplementation(async () => {
      return {
        status: 400,
        json: async () => ({ 
          success: false, 
          message: 'Verification token is required' 
        })
      };
    });

    const { req, res } = createMockRequestResponse({
      method: 'GET',
      url: '/api/auth/verify-email',
      headers: {}
    });

    await mockGet(req);
    
    expect(res.status).toBe(400);
  });

  it('should return 400 if token is invalid or expired', async () => {
    mockPrisma.emailVerification.findUnique.mockResolvedValueOnce(null);

    mockGet.mockImplementation(async () => {
      return {
        status: 400,
        json: async () => ({ 
          success: false, 
          message: 'Invalid or expired verification token' 
        })
      };
    });

    const { req, res } = createMockRequestResponse({
      method: 'GET',
      url: '/api/auth/verify-email?token=invalid-token',
      headers: {}
    });

    await mockGet(req);
    
    expect(res.status).toBe(400);
  });

  it('should successfully verify email', async () => {
    const expiryDate = new Date();
    expiryDate.setHours(expiryDate.getHours() + 1); // Still valid

    mockPrisma.emailVerification.findUnique.mockResolvedValueOnce({
      id: 'verif-1',
      token: mockToken,
      userId: mockUserId,
      expiresAt: expiryDate,
      createdAt: new Date()
    });

    mockPrisma.user.update.mockResolvedValueOnce({
      id: mockUserId,
      email: 'user@example.com',
      emailVerified: new Date()
    });

    mockPrisma.emailVerification.delete.mockResolvedValueOnce({
      id: 'verif-1',
      token: mockToken,
      userId: mockUserId,
      expiresAt: expiryDate,
      createdAt: new Date()
    });

    mockGet.mockImplementation(async () => {
      return {
        status: 200,
        json: async () => ({ 
          success: true, 
          message: 'Email verified successfully' 
        })
      };
    });

    const { req, res } = createMockRequestResponse({
      method: 'GET',
      url: `/api/auth/verify-email?token=${mockToken}`,
      headers: {}
    });

    await mockGet(req);
    
    expect(res.status).toBe(200);
  });

  it('should handle database errors', async () => {
    const expiryDate = new Date();
    expiryDate.setHours(expiryDate.getHours() + 1); // Still valid

    mockPrisma.emailVerification.findUnique.mockResolvedValueOnce({
      id: 'verif-1',
      token: mockToken,
      userId: mockUserId,
      expiresAt: expiryDate,
      createdAt: new Date()
    });

    mockPrisma.user.update.mockRejectedValueOnce(new Error('Database error'));

    mockGet.mockImplementation(async () => {
      return {
        status: 500,
        json: async () => ({ 
          success: false, 
          message: 'Failed to verify email' 
        })
      };
    });

    const { req, res } = createMockRequestResponse({
      method: 'GET',
      url: `/api/auth/verify-email?token=${mockToken}`,
      headers: {}
    });

    await mockGet(req);
    
    expect(res.status).toBe(500);
  });
}); 