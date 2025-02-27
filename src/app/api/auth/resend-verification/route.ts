import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/app/api/auth/[...nextauth]/route";
import { prisma } from "@/lib/prisma";
import { generateVerificationToken } from "../verify-email/route";
import { sendVerificationEmail } from "@/lib/email";

export async function POST(req: NextRequest) {
  try {
    const session = await getServerSession(authOptions);
    
    if (!session || !session.user) {
      return NextResponse.json(
        { success: false, message: "Unauthorized" },
        { status: 401 }
      );
    }
    
    const { email } = await req.json();
    
    // Verify this is the user's own email
    if (email !== session.user.email) {
      return NextResponse.json(
        { success: false, message: "Unauthorized" },
        { status: 401 }
      );
    }
    
    const user = await prisma.user.findUnique({
      where: { email },
    });
    
    if (!user) {
      return NextResponse.json(
        { success: false, message: "User not found" },
        { status: 404 }
      );
    }
    
    // Check if email is already verified
    if (user.emailVerified) {
      return NextResponse.json(
        { success: false, message: "Email is already verified" },
        { status: 400 }
      );
    }
    
    // Generate new verification token
    const verificationToken = generateVerificationToken(email);
    const tokenExpiry = new Date();
    tokenExpiry.setHours(tokenExpiry.getHours() + 24); // Token valid for 24 hours
    
    // Update user with new token
    await prisma.user.update({
      where: { email },
      data: {
        emailVerificationToken: verificationToken,
        emailVerificationExpires: tokenExpiry,
      },
    });
    
    // Send verification email
    await sendVerificationEmail(email, verificationToken);
    
    return NextResponse.json({
      success: true,
      message: "Verification email sent successfully",
    });
  } catch (error) {
    console.error("Resend verification error:", error);
    return NextResponse.json(
      { success: false, message: "Failed to send verification email" },
      { status: 500 }
    );
  }
} 