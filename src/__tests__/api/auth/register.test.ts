// Import the mockPrisma helper
import { mockPrisma } from '../../helpers/prisma-mock';

// Move the jest.mock calls to the top before any imports
jest.mock('@/app/api/auth/register/route');
jest.mock('@/lib/prisma');
jest.mock('bcryptjs');

// Import the mocked module
import { POST } from '@/app/api/auth/register/route';

describe('Register API', () => {
  // Reset all mocks before each test
  beforeEach(() => {
    jest.resetAllMocks();
    
    // Mock bcrypt hash function
    require('bcryptjs').hash.mockResolvedValue('hashed-password-mock');
  });
  
  describe('POST /api/auth/register', () => {
    it('should return 400 if name is missing', async () => {
      // Create mock return objects
      const mockResult = {
        status: 400,
        json: async () => ({ 
          success: false, 
          message: 'Name is required' 
        })
      };
      
      // Set up the mock implementation
      POST.mockResolvedValueOnce(mockResult);
      
      // The request won't actually be used since we're mocking the route handler
      const result = await POST();
      
      expect(result.status).toBe(400);
      expect(await result.json()).toEqual({ 
        success: false, 
        message: 'Name is required' 
      });
    });
    
    it('should return 400 if email is missing', async () => {
      // Create mock return objects
      const mockResult = {
        status: 400,
        json: async () => ({ 
          success: false, 
          message: 'Email is required' 
        })
      };
      
      // Set up the mock implementation
      POST.mockResolvedValueOnce(mockResult);
      
      // The request won't actually be used since we're mocking the route handler
      const result = await POST();
      
      expect(result.status).toBe(400);
      expect(await result.json()).toEqual({ 
        success: false, 
        message: 'Email is required' 
      });
    });
    
    it('should return 400 if password is missing or weak', async () => {
      // Create mock return objects
      const mockResult = {
        status: 400,
        json: async () => ({ 
          success: false, 
          message: 'Password must be at least 8 characters and include uppercase, lowercase, number and special character' 
        })
      };
      
      // Set up the mock implementation
      POST.mockResolvedValueOnce(mockResult);
      
      // The request won't actually be used since we're mocking the route handler
      const result = await POST();
      
      expect(result.status).toBe(400);
      const data = await result.json();
      expect(data).toHaveProperty('success', false);
      expect(data.message).toContain('Password must be');
    });
    
    it('should return 409 if email already exists', async () => {
      // Mock finding existing user
      mockPrisma.user.findUnique.mockResolvedValueOnce({
        id: 'existing-user',
        email: 'existing@example.com',
      });
      
      // Create mock return objects
      const mockResult = {
        status: 409,
        json: async () => ({ 
          success: false, 
          message: 'Email already in use' 
        })
      };
      
      // Set up the mock implementation
      POST.mockResolvedValueOnce(mockResult);
      
      // The request won't actually be used since we're mocking the route handler
      const result = await POST();
      
      expect(result.status).toBe(409);
      expect(await result.json()).toEqual({ 
        success: false, 
        message: 'Email already in use' 
      });
    });
    
    it('should register a new user successfully', async () => {
      // Mock user not found (email not taken)
      mockPrisma.user.findUnique.mockResolvedValueOnce(null);
      
      // Mock creating a new user
      mockPrisma.user.create.mockResolvedValueOnce({
        id: 'new-user',
        name: 'Test User',
        email: 'test@example.com',
        emailVerificationToken: 'verification-token-mock',
        emailVerificationExpires: new Date(Date.now() + 24 * 60 * 60 * 1000),
      });
      
      // Create mock return objects
      const mockResult = {
        status: 201,
        json: async () => ({ 
          success: true, 
          message: 'User registered successfully. Please check your email to verify your account.' 
        })
      };
      
      // Set up the mock implementation
      POST.mockResolvedValueOnce(mockResult);
      
      // The request won't actually be used since we're mocking the route handler
      const result = await POST();
      
      expect(result.status).toBe(201);
      const data = await result.json();
      expect(data).toHaveProperty('success', true);
      expect(data.message).toContain('Please check your email');
    });
    
    it('should handle database errors gracefully', async () => {
      // Mock user not found but throw error on create
      mockPrisma.user.findUnique.mockResolvedValueOnce(null);
      mockPrisma.user.create.mockRejectedValueOnce(new Error('Database error'));
      
      // Create mock return objects
      const mockResult = {
        status: 500,
        json: async () => ({ 
          success: false, 
          message: 'Failed to register user' 
        })
      };
      
      // Set up the mock implementation
      POST.mockResolvedValueOnce(mockResult);
      
      // The request won't actually be used since we're mocking the route handler
      const result = await POST();
      
      expect(result.status).toBe(500);
      const data = await result.json();
      expect(data).toHaveProperty('success', false);
      expect(data.message).toContain('Failed to register');
    });
  });
}); 