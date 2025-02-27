import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { createHash } from "crypto";

export async function GET(req: NextRequest) {
  const searchParams = req.nextUrl.searchParams;
  const token = searchParams.get("token");
  
  if (!token) {
    return NextResponse.redirect(new URL("/login?error=invalid-token", req.url));
  }
  
  try {
    // Find user with this verification token
    const user = await prisma.user.findFirst({
      where: {
        emailVerificationToken: token,
        emailVerificationExpires: {
          gt: new Date(),
        },
      },
    });
    
    if (!user) {
      return NextResponse.redirect(new URL("/login?error=invalid-token", req.url));
    }
    
    // Update user as verified
    await prisma.user.update({
      where: { id: user.id },
      data: {
        emailVerified: new Date(),
        emailVerificationToken: null,
        emailVerificationExpires: null,
      },
    });
    
    return NextResponse.redirect(new URL("/login?verified=true", req.url));
  } catch (error) {
    console.error("Email verification error:", error);
    return NextResponse.redirect(new URL("/login?error=verification-failed", req.url));
  }
}

// Function to generate verification token
export function generateVerificationToken(email: string): string {
  const timestamp = Date.now().toString();
  return createHash("sha256").update(`${email}${timestamp}`).digest("hex");
} 