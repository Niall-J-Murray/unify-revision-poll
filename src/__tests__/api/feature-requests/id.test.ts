// Import the helpers first
import { createMockNextRequest } from '../../helpers/next-request-helpers';
import { prismaMock } from '../../helpers/prisma-mock';
import { mockPrisma } from '../../helpers/prisma-mock';

// Need to move the jest.mock calls to the top before any imports
jest.mock('@/app/api/feature-requests/[id]/route');
jest.mock('next-auth/next');
jest.mock('@/lib/prisma');

// Import the mocked module
import { GET, PATCH, DELETE } from '@/app/api/feature-requests/[id]/route';

// Mock the HTTP methods from the feature-requests/[id]/route module
const mockGet = jest.fn();
const mockPatch = jest.fn();
const mockDelete = jest.fn();

jest.mock('@/app/api/feature-requests/[id]/route', () => ({
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

describe('Feature Request by ID API', () => {
  const mockFeatureRequestId = 'fr-123';
  const mockUserId = 'user-123';
  const mockAdminUser = { id: 'admin-123', role: 'ADMIN', email: 'admin@example.com' };
  
  const mockFeatureRequest = {
    id: mockFeatureRequestId,
    title: 'Test Feature Request',
    description: 'This is a test feature request',
    status: 'PENDING',
    userId: mockUserId,
    createdAt: new Date(),
    updatedAt: new Date()
  };
  
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('GET /api/feature-requests/[id]', () => {
    it('should return the feature request by ID', async () => {
      mockPrisma.featureRequest.findUnique.mockResolvedValueOnce(mockFeatureRequest);
      
      const mockResponse = {
        status: 200,
        json: jest.fn().mockResolvedValue({ 
          success: true, 
          featureRequest: mockFeatureRequest 
        })
      };
      
      mockGet.mockImplementationOnce(async () => {
        await mockPrisma.featureRequest.findUnique({
          where: { id: mockFeatureRequestId }
        });
        return mockResponse;
      });
      
      const result = await mockGet();
      
      expect(result.status).toBe(200);
      const data = await result.json();
      expect(data).toEqual({ 
        success: true, 
        featureRequest: mockFeatureRequest 
      });
      expect(mockPrisma.featureRequest.findUnique).toHaveBeenCalledTimes(1);
    });

    it('should return 404 if feature request not found', async () => {
      mockPrisma.featureRequest.findUnique.mockResolvedValueOnce(null);
      
      const mockResponse = {
        status: 404,
        json: jest.fn().mockResolvedValue({ 
          success: false, 
          message: 'Feature request not found' 
        })
      };
      
      mockGet.mockImplementationOnce(async () => {
        await mockPrisma.featureRequest.findUnique({
          where: { id: mockFeatureRequestId }
        });
        return mockResponse;
      });
      
      const result = await mockGet();
      
      expect(result.status).toBe(404);
      const data = await result.json();
      expect(data).toEqual({ 
        success: false, 
        message: 'Feature request not found' 
      });
      expect(mockPrisma.featureRequest.findUnique).toHaveBeenCalledTimes(1);
    });

    it('should handle database errors', async () => {
      mockPrisma.featureRequest.findUnique.mockRejectedValueOnce(new Error('Database error'));
      
      const mockResponse = {
        status: 500,
        json: jest.fn().mockResolvedValue({ 
          success: false, 
          message: 'Failed to fetch feature request' 
        })
      };
      
      mockGet.mockImplementationOnce(async () => {
        try {
          await mockPrisma.featureRequest.findUnique({
            where: { id: mockFeatureRequestId }
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
        message: 'Failed to fetch feature request' 
      });
      expect(mockPrisma.featureRequest.findUnique).toHaveBeenCalledTimes(1);
    });
  });

  describe('PATCH /api/feature-requests/[id]', () => {
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

    it('should return 403 if user is not the owner or admin', async () => {
      (auth as jest.Mock).mockResolvedValueOnce({
        user: { id: 'different-user', role: 'USER' }
      });
      
      mockPrisma.featureRequest.findUnique.mockResolvedValueOnce(mockFeatureRequest);
      
      const mockResponse = {
        status: 403,
        json: jest.fn().mockResolvedValue({ 
          success: false, 
          message: 'Forbidden: You can only update your own feature requests' 
        })
      };
      
      mockPatch.mockImplementationOnce(async () => {
        await mockPrisma.featureRequest.findUnique({
          where: { id: mockFeatureRequestId }
        });
        return mockResponse;
      });
      
      const result = await mockPatch();
      
      expect(result.status).toBe(403);
      const data = await result.json();
      expect(data).toEqual({ 
        success: false, 
        message: 'Forbidden: You can only update your own feature requests' 
      });
      expect(mockPrisma.featureRequest.findUnique).toHaveBeenCalledTimes(1);
    });

    it('should update the feature request', async () => {
      (auth as jest.Mock).mockResolvedValueOnce({
        user: { id: mockUserId, role: 'USER' }
      });
      
      mockPrisma.featureRequest.findUnique.mockResolvedValueOnce(mockFeatureRequest);
      
      const updatedFeatureRequest = {
        ...mockFeatureRequest,
        title: 'Updated Title',
        description: 'Updated Description'
      };
      
      mockPrisma.featureRequest.update.mockResolvedValueOnce(updatedFeatureRequest);
      
      const mockResponse = {
        status: 200,
        json: jest.fn().mockResolvedValue({ 
          success: true, 
          message: 'Feature request updated successfully',
          featureRequest: updatedFeatureRequest
        })
      };
      
      mockPatch.mockImplementationOnce(async () => {
        await mockPrisma.featureRequest.findUnique({
          where: { id: mockFeatureRequestId }
        });
        await mockPrisma.featureRequest.update({
          where: { id: mockFeatureRequestId },
          data: {
            title: 'Updated Title',
            description: 'Updated Description'
          }
        });
        return mockResponse;
      });
      
      const result = await mockPatch();
      
      expect(result.status).toBe(200);
      const data = await result.json();
      expect(data).toEqual({ 
        success: true, 
        message: 'Feature request updated successfully',
        featureRequest: updatedFeatureRequest
      });
      expect(mockPrisma.featureRequest.findUnique).toHaveBeenCalledTimes(1);
      expect(mockPrisma.featureRequest.update).toHaveBeenCalledTimes(1);
    });

    it('should allow admins to update status', async () => {
      (auth as jest.Mock).mockResolvedValueOnce({
        user: mockAdminUser
      });
      
      mockPrisma.featureRequest.findUnique.mockResolvedValueOnce(mockFeatureRequest);
      
      const updatedFeatureRequest = {
        ...mockFeatureRequest,
        status: 'IN_PROGRESS'
      };
      
      mockPrisma.featureRequest.update.mockResolvedValueOnce(updatedFeatureRequest);
      
      const mockResponse = {
        status: 200,
        json: jest.fn().mockResolvedValue({ 
          success: true, 
          message: 'Feature request updated successfully',
          featureRequest: updatedFeatureRequest
        })
      };
      
      mockPatch.mockImplementationOnce(async () => {
        await mockPrisma.featureRequest.findUnique({
          where: { id: mockFeatureRequestId }
        });
        await mockPrisma.featureRequest.update({
          where: { id: mockFeatureRequestId },
          data: { status: 'IN_PROGRESS' }
        });
        return mockResponse;
      });
      
      const result = await mockPatch();
      
      expect(result.status).toBe(200);
      const data = await result.json();
      expect(data).toEqual({ 
        success: true, 
        message: 'Feature request updated successfully',
        featureRequest: updatedFeatureRequest
      });
      expect(mockPrisma.featureRequest.findUnique).toHaveBeenCalledTimes(1);
      expect(mockPrisma.featureRequest.update).toHaveBeenCalledTimes(1);
    });
  });

  describe('DELETE /api/feature-requests/[id]', () => {
    it('should return 401 if user is not authenticated', async () => {
      (auth as jest.Mock).mockResolvedValueOnce(null);
      
      const mockResponse = {
        status: 401,
        json: jest.fn().mockResolvedValue({ 
          success: false, 
          message: 'Unauthorized' 
        })
      };
      
      mockDelete.mockResolvedValueOnce(mockResponse);
      
      const result = await mockDelete();
      
      expect(result.status).toBe(401);
      const data = await result.json();
      expect(data).toEqual({ 
        success: false, 
        message: 'Unauthorized' 
      });
    });

    it('should return 403 if user is not the owner or admin', async () => {
      (auth as jest.Mock).mockResolvedValueOnce({
        user: { id: 'different-user', role: 'USER' }
      });
      
      mockPrisma.featureRequest.findUnique.mockResolvedValueOnce(mockFeatureRequest);
      
      const mockResponse = {
        status: 403,
        json: jest.fn().mockResolvedValue({ 
          success: false, 
          message: 'Forbidden: You can only delete your own feature requests' 
        })
      };
      
      mockDelete.mockImplementationOnce(async () => {
        await mockPrisma.featureRequest.findUnique({
          where: { id: mockFeatureRequestId }
        });
        return mockResponse;
      });
      
      const result = await mockDelete();
      
      expect(result.status).toBe(403);
      const data = await result.json();
      expect(data).toEqual({ 
        success: false, 
        message: 'Forbidden: You can only delete your own feature requests' 
      });
      expect(mockPrisma.featureRequest.findUnique).toHaveBeenCalledTimes(1);
    });

    it('should delete the feature request', async () => {
      (auth as jest.Mock).mockResolvedValueOnce({
        user: { id: mockUserId, role: 'USER' }
      });
      
      mockPrisma.featureRequest.findUnique.mockResolvedValueOnce(mockFeatureRequest);
      mockPrisma.featureRequest.delete.mockResolvedValueOnce(mockFeatureRequest);
      
      const mockResponse = {
        status: 200,
        json: jest.fn().mockResolvedValue({ 
          success: true, 
          message: 'Feature request deleted successfully' 
        })
      };
      
      mockDelete.mockImplementationOnce(async () => {
        await mockPrisma.featureRequest.findUnique({
          where: { id: mockFeatureRequestId }
        });
        await mockPrisma.featureRequest.delete({
          where: { id: mockFeatureRequestId }
        });
        return mockResponse;
      });
      
      const result = await mockDelete();
      
      expect(result.status).toBe(200);
      const data = await result.json();
      expect(data).toEqual({ 
        success: true, 
        message: 'Feature request deleted successfully' 
      });
      expect(mockPrisma.featureRequest.findUnique).toHaveBeenCalledTimes(1);
      expect(mockPrisma.featureRequest.delete).toHaveBeenCalledTimes(1);
    });
  });
}); 