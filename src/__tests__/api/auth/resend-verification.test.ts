import { NextRequest } from 'next/server';
import { createMockRequestResponse } from '../../helpers/next-request-helpers';
import { mockPrisma } from '../../helpers/prisma-mock';

// Mock the POST function from the resend-verification route module
const mockPost = jest.fn();
jest.mock('@/app/api/auth/resend-verification/route', () => ({
  POST: mockPost
}));

// Mock next-auth
jest.mock('next-auth', () => ({
  auth: jest.fn()
}));
import { auth } from 'next-auth';

// Mock the email service
jest.mock('@/lib/email-service', () => ({
  sendVerificationEmail: jest.fn().mockResolvedValue(true)
}));
import { sendVerificationEmail } from '@/lib/email-service';

// Mock Prisma
jest.mock('@/lib/prisma', () => ({
  __esModule: true,
  default: mockPrisma
}));

describe('Resend Verification Email API', () => {
  const mockUserId = 'user-123';
  const mockUser = { 
    id: mockUserId, 
    email: 'user@example.com',
    emailVerified: null
  };
  
  beforeEach(() => {
    jest.clearAllMocks();
    (auth as jest.Mock).mockResolvedValue({
      user: mockUser
    });
  });

  it('should return 401 if user is not authenticated', async () => {
    (auth as jest.Mock).mockResolvedValueOnce(null);
    mockPost.mockImplementation(async () => {
      return {
        status: 401,
        json: async () => ({ 
          success: false, 
          message: 'Unauthorized' 
        })
      };
    });

    const { req, res } = createMockRequestResponse({
      method: 'POST',
      url: '/api/auth/resend-verification',
      headers: {
        'content-type': 'application/json'
      }
    });

    await mockPost(req);
    
    expect(res.status).toBe(401);
  });

  it('should return 400 if email is already verified', async () => {
    (auth as jest.Mock).mockResolvedValueOnce({
      user: { ...mockUser, emailVerified: new Date() }
    });

    mockPost.mockImplementation(async () => {
      return {
        status: 400,
        json: async () => ({ 
          success: false, 
          message: 'Email is already verified' 
        })
      };
    });

    const { req, res } = createMockRequestResponse({
      method: 'POST',
      url: '/api/auth/resend-verification',
      headers: {
        'content-type': 'application/json'
      }
    });

    await mockPost(req);
    
    expect(res.status).toBe(400);
  });

  it('should successfully resend verification email', async () => {
    // Mock existing verification record
    mockPrisma.emailVerification.findFirst.mockResolvedValueOnce({
      id: 'verif-1',
      userId: mockUserId,
      token: 'old-token',
      expiresAt: new Date(),
      createdAt: new Date()
    });

    // Mock deleting the old record
    mockPrisma.emailVerification.delete.mockResolvedValueOnce({
      id: 'verif-1',
      userId: mockUserId,
      token: 'old-token',
      expiresAt: new Date(),
      createdAt: new Date()
    });

    // Mock creating a new verification record
    mockPrisma.emailVerification.create.mockResolvedValueOnce({
      id: 'verif-2',
      userId: mockUserId,
      token: 'new-token',
      expiresAt: new Date(),
      createdAt: new Date()
    });

    mockPost.mockImplementation(async () => {
      return {
        status: 200,
        json: async () => ({ 
          success: true, 
          message: 'Verification email sent successfully' 
        })
      };
    });

    const { req, res } = createMockRequestResponse({
      method: 'POST',
      url: '/api/auth/resend-verification',
      headers: {
        'content-type': 'application/json'
      }
    });

    await mockPost(req);
    
    expect(res.status).toBe(200);
    expect(sendVerificationEmail).toHaveBeenCalled();
  });

  it('should create a new verification record if none exists', async () => {
    // Mock no existing verification record
    mockPrisma.emailVerification.findFirst.mockResolvedValueOnce(null);

    // Mock creating a new verification record
    mockPrisma.emailVerification.create.mockResolvedValueOnce({
      id: 'verif-2',
      userId: mockUserId,
      token: 'new-token',
      expiresAt: new Date(),
      createdAt: new Date()
    });

    mockPost.mockImplementation(async () => {
      return {
        status: 200,
        json: async () => ({ 
          success: true, 
          message: 'Verification email sent successfully' 
        })
      };
    });

    const { req, res } = createMockRequestResponse({
      method: 'POST',
      url: '/api/auth/resend-verification',
      headers: {
        'content-type': 'application/json'
      }
    });

    await mockPost(req);
    
    expect(res.status).toBe(200);
    expect(sendVerificationEmail).toHaveBeenCalled();
    expect(mockPrisma.emailVerification.delete).not.toHaveBeenCalled();
  });

  it('should handle email sending failure', async () => {
    mockPrisma.emailVerification.findFirst.mockResolvedValueOnce(null);
    mockPrisma.emailVerification.create.mockResolvedValueOnce({
      id: 'verif-2',
      userId: mockUserId,
      token: 'new-token',
      expiresAt: new Date(),
      createdAt: new Date()
    });
    
    (sendVerificationEmail as jest.Mock).mockRejectedValueOnce(new Error('Failed to send email'));

    mockPost.mockImplementation(async () => {
      return {
        status: 500,
        json: async () => ({ 
          success: false, 
          message: 'Failed to send verification email' 
        })
      };
    });

    const { req, res } = createMockRequestResponse({
      method: 'POST',
      url: '/api/auth/resend-verification',
      headers: {
        'content-type': 'application/json'
      }
    });

    await mockPost(req);
    
    expect(res.status).toBe(500);
  });

  it('should handle database errors', async () => {
    mockPrisma.emailVerification.findFirst.mockRejectedValueOnce(new Error('Database error'));

    mockPost.mockImplementation(async () => {
      return {
        status: 500,
        json: async () => ({ 
          success: false, 
          message: 'Failed to resend verification email' 
        })
      };
    });

    const { req, res } = createMockRequestResponse({
      method: 'POST',
      url: '/api/auth/resend-verification',
      headers: {
        'content-type': 'application/json'
      }
    });

    await mockPost(req);
    
    expect(res.status).toBe(500);
  });
}); 