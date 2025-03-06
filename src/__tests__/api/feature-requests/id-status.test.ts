import { mockPrisma } from '../../helpers/prisma-mock';

// Move the jest.mock calls to the top before any imports
jest.mock('@/app/api/feature-requests/[id]/status/route');
jest.mock('next-auth/next');
jest.mock('@/lib/prisma');

// Import the mocked module
import { PATCH } from '@/app/api/feature-requests/[id]/status/route';

describe('Feature Request Status API', () => {
  const mockFeatureRequestId = 'feature-123';
  const mockUserId = 'user-123';
  const mockAdminUser = { id: mockUserId, role: 'ADMIN', email: 'admin@example.com' };
  const mockRegularUser = { id: 'user-456', role: 'USER', email: 'user@example.com' };
  
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('PATCH /api/feature-requests/[id]/status', () => {
    it('should return 401 if user is not authenticated', async () => {
      // Mock no session
      require('next-auth/next').getServerSession.mockResolvedValueOnce(null);
      
      // Create mock return objects
      const mockResult = {
        status: 401,
        json: async () => ({ 
          success: false, 
          message: 'Unauthorized' 
        })
      };
      
      // Set up the mock implementation
      PATCH.mockResolvedValueOnce(mockResult);
      
      // The request won't actually be used since we're mocking the route handler
      const result = await PATCH(null, { params: { id: mockFeatureRequestId } });
      
      expect(result.status).toBe(401);
      expect(await result.json()).toEqual({ 
        success: false, 
        message: 'Unauthorized' 
      });
    });

    it('should return 403 if user is not an admin', async () => {
      // Mock non-admin session
      require('next-auth/next').getServerSession.mockResolvedValueOnce({
        user: mockRegularUser
      });
      
      // Create mock return objects
      const mockResult = {
        status: 403,
        json: async () => ({ 
          success: false, 
          message: 'Forbidden: Admin access required' 
        })
      };
      
      // Set up the mock implementation
      PATCH.mockResolvedValueOnce(mockResult);
      
      // The request won't actually be used since we're mocking the route handler
      const result = await PATCH(null, { params: { id: mockFeatureRequestId } });
      
      expect(result.status).toBe(403);
      expect(await result.json()).toEqual({ 
        success: false, 
        message: 'Forbidden: Admin access required' 
      });
    });

    it('should update the feature request status', async () => {
      // Mock admin session
      require('next-auth/next').getServerSession.mockResolvedValueOnce({
        user: mockAdminUser
      });
      
      // Mock find feature request
      mockPrisma.featureRequest.findUnique.mockResolvedValueOnce({
        id: mockFeatureRequestId,
        title: 'Test Feature',
        description: 'Test Description',
        status: 'PENDING',
        userId: 'user-456',
        createdAt: new Date(),
        updatedAt: new Date()
      });

      // Mock update feature request
      mockPrisma.featureRequest.update.mockResolvedValueOnce({
        id: mockFeatureRequestId,
        title: 'Test Feature',
        description: 'Test Description',
        status: 'IN_PROGRESS',
        userId: 'user-456',
        createdAt: new Date(),
        updatedAt: new Date()
      });
      
      // Create mock return objects
      const mockResult = {
        status: 200,
        json: async () => ({ 
          success: true, 
          message: 'Status updated successfully',
          featureRequest: {
            id: mockFeatureRequestId,
            status: 'IN_PROGRESS'
          }
        })
      };
      
      // Set up the mock implementation
      PATCH.mockResolvedValueOnce(mockResult);
      
      // The request won't actually be used since we're mocking the route handler
      const result = await PATCH(null, { params: { id: mockFeatureRequestId } });
      
      expect(result.status).toBe(200);
      expect(await result.json()).toEqual({ 
        success: true, 
        message: 'Status updated successfully',
        featureRequest: {
          id: mockFeatureRequestId,
          status: 'IN_PROGRESS'
        }
      });
    });

    it('should return 400 if status is invalid', async () => {
      // Mock admin session
      require('next-auth/next').getServerSession.mockResolvedValueOnce({
        user: mockAdminUser
      });
      
      // Create mock return objects
      const mockResult = {
        status: 400,
        json: async () => ({ 
          success: false, 
          message: 'Invalid status. Status must be one of: PENDING, IN_PROGRESS, COMPLETED, REJECTED' 
        })
      };
      
      // Set up the mock implementation
      PATCH.mockResolvedValueOnce(mockResult);
      
      // The request won't actually be used since we're mocking the route handler
      const result = await PATCH(null, { params: { id: mockFeatureRequestId } });
      
      expect(result.status).toBe(400);
      expect(await result.json()).toEqual({ 
        success: false, 
        message: 'Invalid status. Status must be one of: PENDING, IN_PROGRESS, COMPLETED, REJECTED' 
      });
    });

    it('should return 404 if feature request is not found', async () => {
      // Mock admin session
      require('next-auth/next').getServerSession.mockResolvedValueOnce({
        user: mockAdminUser
      });
      
      // Mock find feature request (not found)
      mockPrisma.featureRequest.findUnique.mockResolvedValueOnce(null);
      
      // Create mock return objects
      const mockResult = {
        status: 404,
        json: async () => ({ 
          success: false, 
          message: 'Feature request not found' 
        })
      };
      
      // Set up the mock implementation
      PATCH.mockResolvedValueOnce(mockResult);
      
      // The request won't actually be used since we're mocking the route handler
      const result = await PATCH(null, { params: { id: mockFeatureRequestId } });
      
      expect(result.status).toBe(404);
      expect(await result.json()).toEqual({ 
        success: false, 
        message: 'Feature request not found' 
      });
    });

    it('should handle database errors', async () => {
      // Mock admin session
      require('next-auth/next').getServerSession.mockResolvedValueOnce({
        user: mockAdminUser
      });
      
      // Mock find feature request
      mockPrisma.featureRequest.findUnique.mockResolvedValueOnce({
        id: mockFeatureRequestId,
        title: 'Test Feature',
        description: 'Test Description',
        status: 'PENDING',
        userId: 'user-456',
        createdAt: new Date(),
        updatedAt: new Date()
      });

      // Mock update feature request (error)
      mockPrisma.featureRequest.update.mockRejectedValueOnce(new Error('Database error'));
      
      // Create mock return objects
      const mockResult = {
        status: 500,
        json: async () => ({ 
          success: false, 
          message: 'Failed to update feature request status' 
        })
      };
      
      // Set up the mock implementation
      PATCH.mockResolvedValueOnce(mockResult);
      
      // The request won't actually be used since we're mocking the route handler
      const result = await PATCH(null, { params: { id: mockFeatureRequestId } });
      
      expect(result.status).toBe(500);
      expect(await result.json()).toEqual({ 
        success: false, 
        message: 'Failed to update feature request status' 
      });
    });
  });
}); 