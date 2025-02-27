// Simple in-memory store for rate limiting
// In production, you'd want to use Redis or another persistent store
const loginAttempts: Record<string, { count: number; resetTime: number }> = {};

// Rate limit configuration
const MAX_ATTEMPTS = 5; // Maximum login attempts
const WINDOW_MS = 15 * 60 * 1000; // 15 minutes window

export function checkLoginRateLimit(identifier: string): {
  success: boolean;
  message?: string;
  remainingAttempts?: number;
  resetTime?: Date;
} {
  const now = Date.now();
  const ipData = loginAttempts[identifier];

  // If no previous attempts or window has expired
  if (!ipData || ipData.resetTime < now) {
    loginAttempts[identifier] = {
      count: 1,
      resetTime: now + WINDOW_MS,
    };
    return { 
      success: true,
      remainingAttempts: MAX_ATTEMPTS - 1,
      resetTime: new Date(now + WINDOW_MS)
    };
  }

  // If within window but under max attempts
  if (ipData.count < MAX_ATTEMPTS) {
    ipData.count += 1;
    const remaining = MAX_ATTEMPTS - ipData.count;
    
    return { 
      success: true,
      remainingAttempts: remaining,
      resetTime: new Date(ipData.resetTime)
    };
  }

  // Rate limit exceeded
  const resetTime = new Date(ipData.resetTime);
  return {
    success: false,
    message: `Too many login attempts. Please try again after ${resetTime.toLocaleTimeString()}.`,
    resetTime
  };
}

export function resetLoginAttempts(identifier: string): void {
  delete loginAttempts[identifier];
} 