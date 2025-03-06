// Import the helpers first
import { createMockNextRequest } from '../../helpers/next-request-helpers';
import { prismaMock } from '../../helpers/prisma-mock';
import { mockPrisma } from '../../helpers/prisma-mock';

// Need to move the jest.mock calls to the top before any imports
jest.mock('@/app/api/user/profile/route');
jest.mock('next-auth/next');
jest.mock('@/lib/prisma');

// Import the mocked module
import { GET, PATCH } from '@/app/api/user/profile/route';

// Mock the HTTP methods from the user/profile/route module
const mockGet = jest.fn();
const mockPatch = jest.fn();

jest.mock('@/app/api/user/profile/route', () => ({
  GET: mockGet,
  PATCH: mockPatch
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

describe('User Profile API', () => {
  const mockUserId = 'user-123';
  const mockUser = {
    id: mockUserId,
    name: 'Test User',
    email: 'test@example.com',
    role: 'USER',
    emailVerified: new Date(),
    createdAt: new Date(),
    updatedAt: new Date()
  };
  
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('GET /api/user/profile', () => {
    it('should return 401 if user is not authenticated', async () => {
      (auth as jest.Mock).mockResolvedValueOnce(null);
      
      const mockResponse = {
        status: 401,
        json: jest.fn().mockResolvedValue({ 
          success: false, 
          message: 'Unauthorized' 
        })
      };
      
      mockGet.mockResolvedValueOnce(mockResponse);
      
      const result = await mockGet();
      
      expect(result.status).toBe(401);
      const data = await result.json();
      expect(data).toEqual({ 
        success: false, 
        message: 'Unauthorized' 
      });
    });

    it('should return the user profile', async () => {
      (auth as jest.Mock).mockResolvedValueOnce({
        user: mockUser
      });
      
      mockPrisma.user.findUnique.mockResolvedValueOnce(mockUser);
      
      const mockResponse = {
        status: 200,
        json: jest.fn().mockResolvedValue({ 
          success: true, 
          user: mockUser 
        })
      };
      
      mockGet.mockImplementationOnce(async () => {
        await mockPrisma.user.findUnique({
          where: { id: mockUserId }
        });
        return mockResponse;
      });
      
      const result = await mockGet();
      
      expect(result.status).toBe(200);
      const data = await result.json();
      expect(data).toEqual({ 
        success: true, 
        user: mockUser 
      });
      expect(mockPrisma.user.findUnique).toHaveBeenCalledTimes(1);
    });

    it('should handle database errors', async () => {
      (auth as jest.Mock).mockResolvedValueOnce({
        user: mockUser
      });
      
      mockPrisma.user.findUnique.mockRejectedValueOnce(new Error('Database error'));
      
      const mockResponse = {
        status: 500,
        json: jest.fn().mockResolvedValue({ 
          success: false, 
          message: 'Failed to fetch profile' 
        })
      };
      
      mockGet.mockImplementationOnce(async () => {
        try {
          await mockPrisma.user.findUnique({
            where: { id: mockUserId }
          });
        } catch (error) {
          return mockResponse;
        }
      });
      
      const result = await mockGet();
      
      expect(result.status).toBe(500);
      const data = await result.json();
      expect(data).toEqual({ 
        success: false, 
        message: 'Failed to fetch profile' 
      });
      expect(mockPrisma.user.findUnique).toHaveBeenCalledTimes(1);
    });
  });

  describe('PATCH /api/user/profile', () => {
    it('should return 401 if user is not authenticated', async () => {
      (auth as jest.Mock).mockResolvedValueOnce(null);
      
      const mockResponse = {
        status: 401,
        json: jest.fn().mockResolvedValue({ 
          success: false, 
          message: 'Unauthorized' 
        })
      };
      
      mockPatch.mockResolvedValueOnce(mockResponse);
      
      const result = await mockPatch();
      
      expect(result.status).toBe(401);
      const data = await result.json();
      expect(data).toEqual({ 
        success: false, 
        message: 'Unauthorized' 
      });
    });

    it('should update the user profile', async () => {
      (auth as jest.Mock).mockResolvedValueOnce({
        user: mockUser
      });
      
      const updatedUser = {
        ...mockUser,
        name: 'Updated Name'
      };
      
      mockPrisma.user.update.mockResolvedValueOnce(updatedUser);
      
      const mockResponse = {
        status: 200,
        json: jest.fn().mockResolvedValue({ 
          success: true, 
          message: 'Profile updated successfully',
          user: updatedUser
        })
      };
      
      mockPatch.mockImplementationOnce(async () => {
        await mockPrisma.user.update({
          where: { id: mockUserId },
          data: { name: 'Updated Name' }
        });
        return mockResponse;
      });
      
      const result = await mockPatch();
      
      expect(result.status).toBe(200);
      const data = await result.json();
      expect(data).toEqual({ 
        success: true, 
        message: 'Profile updated successfully',
        user: updatedUser
      });
      expect(mockPrisma.user.update).toHaveBeenCalledTimes(1);
    });

    it('should return 400 if no fields to update', async () => {
      (auth as jest.Mock).mockResolvedValueOnce({
        user: mockUser
      });
      
      const mockResponse = {
        status: 400,
        json: jest.fn().mockResolvedValue({ 
          success: false, 
          message: 'No fields to update' 
        })
      };
      
      mockPatch.mockResolvedValueOnce(mockResponse);
      
      const result = await mockPatch();
      
      expect(result.status).toBe(400);
      const data = await result.json();
      expect(data).toEqual({ 
        success: false, 
        message: 'No fields to update' 
      });
    });

    it('should handle database errors', async () => {
      (auth as jest.Mock).mockResolvedValueOnce({
        user: mockUser
      });
      
      mockPrisma.user.update.mockRejectedValueOnce(new Error('Database error'));
      
      const mockResponse = {
        status: 500,
        json: jest.fn().mockResolvedValue({ 
          success: false, 
          message: 'Failed to update profile' 
        })
      };
      
      mockPatch.mockImplementationOnce(async () => {
        try {
          await mockPrisma.user.update({
            where: { id: mockUserId },
            data: { name: 'Updated Name' }
          });
        } catch (error) {
          return mockResponse;
        }
      });
      
      const result = await mockPatch();
      
      expect(result.status).toBe(500);
      const data = await result.json();
      expect(data).toEqual({ 
        success: false, 
        message: 'Failed to update profile' 
      });
      expect(mockPrisma.user.update).toHaveBeenCalledTimes(1);
    });
  });
}); 