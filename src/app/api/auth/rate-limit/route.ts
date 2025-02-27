import { NextRequest, NextResponse } from "next/server";
import { checkLoginRateLimit, resetLoginAttempts } from "@/lib/rate-limiter";

export async function POST(req: NextRequest) {
  try {
    const { email, success } = await req.json();
    
    // Use IP address as fallback if email is not provided
    const ip = req.headers.get("x-forwarded-for") || "unknown";
    const identifier = email || ip;
    
    // If login was successful, reset rate limit for this identifier
    if (success) {
      resetLoginAttempts(identifier);
      return NextResponse.json({ success: true });
    }
    
    // Check rate limit
    const result = checkLoginRateLimit(identifier);
    
    return NextResponse.json(result);
  } catch (error) {
    console.error("Rate limit error:", error);
    return NextResponse.json(
      { success: false, message: "Internal server error" },
      { status: 500 }
    );
  }
} 