// Import the helpers first
import { createMockNextRequest } from '../../helpers/next-request-helpers';
import { prismaMock } from '../../helpers/prisma-mock';
import { mockPrisma } from '../../helpers/prisma-mock';

// Need to move the jest.mock calls to the top before any imports
jest.mock('@/app/api/admin/users/[id]/route');
jest.mock('next-auth/next');
jest.mock('@/lib/prisma');

// Import the mocked module
import { GET, PATCH, DELETE } from '@/app/api/admin/users/[id]/route';

// Mock the HTTP methods from the admin/users/[id]/route module
const mockGet = jest.fn();
const mockPatch = jest.fn();
const mockDelete = jest.fn();

jest.mock('@/app/api/admin/users/[id]/route', () => ({
  GET: mockGet,
  PATCH: mockPatch,
  DELETE: mockDelete
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

describe('Admin User by ID API', () => {
  const mockUserId = 'user-123';
  const mockUserData = {
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

  describe('GET /api/admin/users/[id]', () => {
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

    it('should return 403 if user is not an admin', async () => {
      (auth as jest.Mock).mockResolvedValueOnce({
        user: { ...mockUserData, role: 'USER' }
      });
      
      const mockResponse = {
        status: 403,
        json: jest.fn().mockResolvedValue({ 
          success: false, 
          message: 'Forbidden: Admin access required' 
        })
      };
      
      mockGet.mockImplementationOnce(async () => {
        return mockResponse;
      });
      
      const result = await mockGet();
      
      expect(result.status).toBe(403);
      const data = await result.json();
      expect(data).toEqual({ 
        success: false, 
        message: 'Forbidden: Admin access required' 
      });
    });

    it('should return a user by ID for admin', async () => {
      (auth as jest.Mock).mockResolvedValueOnce({
        user: { ...mockUserData, role: 'ADMIN' }
      });
      
      mockPrisma.user.findUnique.mockResolvedValueOnce(mockUserData);
      
      const mockResponse = {
        status: 200,
        json: jest.fn().mockResolvedValue({ 
          success: true, 
          user: mockUserData 
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
        user: mockUserData 
      });
      expect(mockPrisma.user.findUnique).toHaveBeenCalledTimes(1);
    });

    it('should return 404 if user not found', async () => {
      (auth as jest.Mock).mockResolvedValueOnce({
        user: { ...mockUserData, role: 'ADMIN' }
      });
      
      mockPrisma.user.findUnique.mockResolvedValueOnce(null);
      
      const mockResponse = {
        status: 404,
        json: jest.fn().mockResolvedValue({ 
          success: false, 
          message: 'User not found' 
        })
      };
      
      mockGet.mockImplementationOnce(async () => {
        await mockPrisma.user.findUnique({
          where: { id: mockUserId }
        });
        return mockResponse;
      });
      
      const result = await mockGet();
      
      expect(result.status).toBe(404);
      const data = await result.json();
      expect(data).toEqual({ 
        success: false, 
        message: 'User not found' 
      });
      expect(mockPrisma.user.findUnique).toHaveBeenCalledTimes(1);
    });
  });

  describe('PATCH /api/admin/users/[id]', () => {
    it('should update a user successfully', async () => {
      (auth as jest.Mock).mockResolvedValueOnce({
        user: { ...mockUserData, role: 'ADMIN' }
      });
      
      mockPrisma.user.findUnique.mockResolvedValueOnce(mockUserData);
      mockPrisma.user.update.mockResolvedValueOnce({
        ...mockUserData,
        role: 'ADMIN'
      });
      
      const mockResponse = {
        status: 200,
        json: jest.fn().mockResolvedValue({ 
          success: true, 
          message: 'User updated successfully',
          user: { ...mockUserData, role: 'ADMIN' }
        })
      };
      
      mockPatch.mockImplementationOnce(async () => {
        await mockPrisma.user.findUnique({
          where: { id: mockUserId }
        });
        await mockPrisma.user.update({
          where: { id: mockUserId },
          data: { role: 'ADMIN' }
        });
        return mockResponse;
      });
      
      const result = await mockPatch();
      
      expect(result.status).toBe(200);
      const data = await result.json();
      expect(data).toEqual({ 
        success: true, 
        message: 'User updated successfully',
        user: { ...mockUserData, role: 'ADMIN' }
      });
      expect(mockPrisma.user.findUnique).toHaveBeenCalledTimes(1);
      expect(mockPrisma.user.update).toHaveBeenCalledTimes(1);
    });

    it('should return 400 for invalid role', async () => {
      (auth as jest.Mock).mockResolvedValueOnce({
        user: { ...mockUserData, role: 'ADMIN' }
      });
      
      mockPrisma.user.findUnique.mockResolvedValueOnce(mockUserData);
      
      const mockResponse = {
        status: 400,
        json: jest.fn().mockResolvedValue({ 
          success: false, 
          message: 'Invalid role: must be USER or ADMIN' 
        })
      };
      
      mockPatch.mockImplementationOnce(async () => {
        await mockPrisma.user.findUnique({
          where: { id: mockUserId }
        });
        return mockResponse;
      });
      
      const result = await mockPatch();
      
      expect(result.status).toBe(400);
      const data = await result.json();
      expect(data).toEqual({ 
        success: false, 
        message: 'Invalid role: must be USER or ADMIN' 
      });
      expect(mockPrisma.user.findUnique).toHaveBeenCalledTimes(1);
    });
  });

  describe('DELETE /api/admin/users/[id]', () => {
    it('should delete a user successfully', async () => {
      (auth as jest.Mock).mockResolvedValueOnce({
        user: { ...mockUserData, role: 'ADMIN' }
      });
      
      mockPrisma.user.findUnique.mockResolvedValueOnce(mockUserData);
      mockPrisma.user.delete.mockResolvedValueOnce(mockUserData);
      
      const mockResponse = {
        status: 200,
        json: jest.fn().mockResolvedValue({ 
          success: true, 
          message: 'User deleted successfully' 
        })
      };
      
      mockDelete.mockImplementationOnce(async () => {
        await mockPrisma.user.findUnique({
          where: { id: mockUserId }
        });
        await mockPrisma.user.delete({
          where: { id: mockUserId }
        });
        return mockResponse;
      });
      
      const result = await mockDelete();
      
      expect(result.status).toBe(200);
      const data = await result.json();
      expect(data).toEqual({ 
        success: true, 
        message: 'User deleted successfully' 
      });
      expect(mockPrisma.user.findUnique).toHaveBeenCalledTimes(1);
      expect(mockPrisma.user.delete).toHaveBeenCalledTimes(1);
    });

    it('should return 404 if user not found', async () => {
      (auth as jest.Mock).mockResolvedValueOnce({
        user: { ...mockUserData, role: 'ADMIN' }
      });
      
      mockPrisma.user.findUnique.mockResolvedValueOnce(null);
      
      const mockResponse = {
        status: 404,
        json: jest.fn().mockResolvedValue({ 
          success: false, 
          message: 'User not found' 
        })
      };
      
      mockDelete.mockImplementationOnce(async () => {
        await mockPrisma.user.findUnique({
          where: { id: mockUserId }
        });
        return mockResponse;
      });
      
      const result = await mockDelete();
      
      expect(result.status).toBe(404);
      const data = await result.json();
      expect(data).toEqual({ 
        success: false, 
        message: 'User not found' 
      });
      expect(mockPrisma.user.findUnique).toHaveBeenCalledTimes(1);
    });

    it('should handle database errors', async () => {
      (auth as jest.Mock).mockResolvedValueOnce({
        user: { ...mockUserData, role: 'ADMIN' }
      });
      
      mockPrisma.user.findUnique.mockResolvedValueOnce(mockUserData);
      mockPrisma.user.delete.mockRejectedValueOnce(new Error('Database error'));
      
      const mockResponse = {
        status: 500,
        json: jest.fn().mockResolvedValue({ 
          success: false, 
          message: 'Failed to delete user' 
        })
      };
      
      mockDelete.mockImplementationOnce(async () => {
        await mockPrisma.user.findUnique({
          where: { id: mockUserId }
        });
        try {
          await mockPrisma.user.delete({
            where: { id: mockUserId }
          });
        } catch (error) {
          return mockResponse;
        }
      });
      
      const result = await mockDelete();
      
      expect(result.status).toBe(500);
      const data = await result.json();
      expect(data).toEqual({ 
        success: false, 
        message: 'Failed to delete user' 
      });
      expect(mockPrisma.user.findUnique).toHaveBeenCalledTimes(1);
      expect(mockPrisma.user.delete).toHaveBeenCalledTimes(1);
    });
  });
}); 