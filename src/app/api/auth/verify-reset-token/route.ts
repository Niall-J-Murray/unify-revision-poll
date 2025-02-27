import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { createHash } from "crypto";

export async function GET(req: NextRequest) {
  try {
    const token = req.nextUrl.searchParams.get("token");
    
    if (!token) {
      return NextResponse.json(
        { valid: false, message: "Missing token" },
        { status: 400 }
      );
    }
    
    // Hash the token to compare with stored hash
    const hashedToken = createHash("sha256").update(token).digest("hex");
    
    // Find user with this reset token
    const user = await prisma.user.findFirst({
      where: {
        resetPasswordToken: hashedToken,
        resetPasswordExpires: {
          gt: new Date(),
        },
      },
    });
    
    if (!user) {
      return NextResponse.json(
        { valid: false, message: "Invalid or expired token" },
        { status: 400 }
      );
    }
    
    return NextResponse.json(
      { valid: true },
      { status: 200 }
    );
  } catch (error) {
    console.error("Token verification error:", error);
    return NextResponse.json(
      { valid: false, message: "Failed to verify token" },
      { status: 500 }
    );
  }
} 