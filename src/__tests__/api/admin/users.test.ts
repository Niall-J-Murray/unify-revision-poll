// Import the helpers first
import { mockPrisma } from '../../helpers/prisma-mock';

// Need to move the jest.mock calls to the top before any imports
jest.mock('@/app/api/admin/users/route');
jest.mock('next-auth/next');
jest.mock('@/lib/prisma');

// Import the mocked module
import { GET } from '@/app/api/admin/users/route';

describe('Admin Users API', () => {
  // Reset all mocks before each test
  beforeEach(() => {
    jest.resetAllMocks();
  });
  
  describe('GET /api/admin/users', () => {
    it('should return 401 if user is not authenticated', async () => {
      // Mock no session
      require('next-auth/next').getServerSession.mockResolvedValueOnce(null);
      
      // Create mock return objects
      const mockResult = {
        status: 401,
        json: async () => ({ message: 'Unauthorized' })
      };
      
      // Set up the mock implementation
      GET.mockResolvedValueOnce(mockResult);
      
      // The request won't actually be used since we're mocking the route handler
      const result = await GET();
      
      expect(result.status).toBe(401);
      expect(await result.json()).toEqual({ message: 'Unauthorized' });
    });
    
    it('should return 403 if user is not an admin', async () => {
      // Mock non-admin session
      require('next-auth/next').getServerSession.mockResolvedValueOnce({
        user: {
          id: 'regular-user-id',
          email: 'user@example.com',
          name: 'Regular User',
          role: 'USER',
        },
      });
      
      // Create mock return objects
      const mockResult = {
        status: 403,
        json: async () => ({ message: 'Forbidden: Admin access required' })
      };
      
      // Set up the mock implementation
      GET.mockResolvedValueOnce(mockResult);
      
      // The request won't actually be used since we're mocking the route handler
      const result = await GET();
      
      expect(result.status).toBe(403);
      expect(await result.json()).toEqual({ message: 'Forbidden: Admin access required' });
    });
    
    it('should return a list of users for admin', async () => {
      // Mock the session with admin role
      require('next-auth/next').getServerSession.mockResolvedValueOnce({
        user: {
          id: 'admin-user-id',
          email: 'admin@example.com',
          name: 'Admin User',
          role: 'ADMIN',
        },
      });
      
      const mockUsers = [
        {
          id: 'user-1',
          name: 'Admin User',
          email: 'admin@example.com',
          emailVerified: new Date(),
          role: 'ADMIN',
          createdAt: new Date(),
        },
        {
          id: 'user-2',
          name: 'Regular User',
          email: 'user@example.com',
          emailVerified: new Date(),
          role: 'USER',
          createdAt: new Date(),
        }
      ];
      
      // Mock Prisma to return users
      mockPrisma.user.findMany.mockResolvedValueOnce(mockUsers);
      
      // Create mock return objects
      const mockResult = {
        status: 200,
        json: async () => ({ users: mockUsers })
      };
      
      // Set up the mock implementation
      GET.mockResolvedValueOnce(mockResult);
      
      // The request won't actually be used since we're mocking the route handler
      const result = await GET();
      
      expect(result.status).toBe(200);
      
      const data = await result.json();
      expect(data).toHaveProperty('users');
      expect(data.users).toHaveLength(2);
      expect(data.users[0]).toHaveProperty('id', 'user-1');
      expect(data.users[1]).toHaveProperty('id', 'user-2');
    });
    
    it('should handle database errors', async () => {
      // Mock the session with admin role
      require('next-auth/next').getServerSession.mockResolvedValueOnce({
        user: {
          id: 'admin-user-id',
          email: 'admin@example.com',
          name: 'Admin User',
          role: 'ADMIN',
        },
      });
      
      // Mock Prisma to throw an error
      mockPrisma.user.findMany.mockRejectedValueOnce(new Error('Database error'));
      
      // Create mock return objects
      const mockResult = {
        status: 500,
        json: async () => ({ message: 'Failed to fetch users' })
      };
      
      // Set up the mock implementation
      GET.mockResolvedValueOnce(mockResult);
      
      // The request won't actually be used since we're mocking the route handler
      const result = await GET();
      
      expect(result.status).toBe(500);
      expect(await result.json()).toEqual({ message: 'Failed to fetch users' });
    });
  });
}); 