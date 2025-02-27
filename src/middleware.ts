import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

// In-memory store for IP-based rate limiting
// In production, use Redis or another persistent store
const ipRequests: Record<string, { count: number; resetTime: number }> = {};

// Rate limit configuration
const MAX_REQUESTS = 100; // Maximum requests per window
const WINDOW_MS = 60 * 1000; // 1 minute window

export function middleware(request: NextRequest) {
  // Only apply rate limiting to auth routes
  if (request.nextUrl.pathname.startsWith('/api/auth')) {
    const ip = request.headers.get('x-forwarded-for') || 'unknown';
    const now = Date.now();
    
    // Initialize or reset if window expired
    if (!ipRequests[ip] || ipRequests[ip].resetTime < now) {
      ipRequests[ip] = {
        count: 1,
        resetTime: now + WINDOW_MS,
      };
      return NextResponse.next();
    }
    
    // Increment count if within limits
    if (ipRequests[ip].count < MAX_REQUESTS) {
      ipRequests[ip].count += 1;
      return NextResponse.next();
    }
    
    // Rate limit exceeded
    return new NextResponse(
      JSON.stringify({ 
        success: false, 
        message: 'Rate limit exceeded. Please try again later.' 
      }),
      { 
        status: 429, 
        headers: { 'Content-Type': 'application/json' } 
      }
    );
  }
  
  return NextResponse.next();
}

export const config = {
  matcher: '/api/auth/:path*',
}; 