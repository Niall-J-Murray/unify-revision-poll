// Mock for Prisma client

const mockUser = {
  id: 'user-1',
  name: 'Test User',
  email: 'test@example.com',
  emailVerified: new Date(),
  password: '$2a$10$mockhashedpassword',
  role: 'USER',
  createdAt: new Date(),
  updatedAt: new Date(),
};

const mockFeatureRequest = {
  id: 'fr-1',
  title: 'Test Feature Request',
  description: 'This is a test feature request',
  createdAt: new Date(),
  updatedAt: new Date(),
  status: 'OPEN',
  userId: 'user-1',
};

const mockVote = {
  id: 'vote-1',
  createdAt: new Date(),
  userId: 'user-1',
  featureRequestId: 'fr-1',
};

export const mockPrisma = {
  user: {
    findUnique: jest.fn().mockResolvedValue(mockUser),
    findMany: jest.fn().mockResolvedValue([mockUser]),
    create: jest.fn().mockResolvedValue(mockUser),
    update: jest.fn().mockResolvedValue(mockUser),
    delete: jest.fn().mockResolvedValue(mockUser),
    count: jest.fn().mockResolvedValue(1),
    findFirst: jest.fn().mockResolvedValue(mockUser),
  },
  featureRequest: {
    findUnique: jest.fn().mockResolvedValue(mockFeatureRequest),
    findMany: jest.fn().mockResolvedValue([mockFeatureRequest]),
    create: jest.fn().mockResolvedValue(mockFeatureRequest),
    update: jest.fn().mockResolvedValue(mockFeatureRequest),
    updateMany: jest.fn().mockResolvedValue({ count: 1 }),
    delete: jest.fn().mockResolvedValue(mockFeatureRequest),
    deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
    count: jest.fn().mockResolvedValue(1),
    findFirst: jest.fn().mockResolvedValue(mockFeatureRequest),
  },
  vote: {
    findUnique: jest.fn().mockResolvedValue(mockVote),
    findMany: jest.fn().mockResolvedValue([mockVote]),
    create: jest.fn().mockResolvedValue(mockVote),
    update: jest.fn().mockResolvedValue(mockVote),
    updateMany: jest.fn().mockResolvedValue({ count: 1 }),
    delete: jest.fn().mockResolvedValue(mockVote),
    deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
    count: jest.fn().mockResolvedValue(1),
    findFirst: jest.fn().mockResolvedValue(mockVote),
  },
  activity: {
    create: jest.fn().mockResolvedValue({ id: 'activity-1' }),
    findMany: jest.fn().mockResolvedValue([]),
    deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
  },
  emailVerification: {
    findUnique: jest.fn().mockResolvedValue({ id: 'ev-1', token: 'token', userId: 'user-1', expiresAt: new Date(), createdAt: new Date() }),
    findFirst: jest.fn().mockResolvedValue({ id: 'ev-1', token: 'token', userId: 'user-1', expiresAt: new Date(), createdAt: new Date() }),
    create: jest.fn().mockResolvedValue({ id: 'ev-1', token: 'token', userId: 'user-1', expiresAt: new Date(), createdAt: new Date() }),
    delete: jest.fn().mockResolvedValue({ id: 'ev-1', token: 'token', userId: 'user-1', expiresAt: new Date(), createdAt: new Date() }),
  },
  passwordReset: {
    findUnique: jest.fn().mockResolvedValue({ id: 'pr-1', token: 'token', userId: 'user-1', expiresAt: new Date(), createdAt: new Date() }),
    create: jest.fn().mockResolvedValue({ id: 'pr-1', token: 'token', userId: 'user-1', expiresAt: new Date(), createdAt: new Date() }),
    delete: jest.fn().mockResolvedValue({ id: 'pr-1', token: 'token', userId: 'user-1', expiresAt: new Date(), createdAt: new Date() }),
  },
  $transaction: jest.fn((callback) => callback(mockPrisma)),
  raw: jest.fn((query) => query),
}; 