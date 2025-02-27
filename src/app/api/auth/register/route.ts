import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { generateVerificationToken } from "../verify-email/route";
import { sendVerificationEmail } from "@/lib/email";
import bcrypt from "bcryptjs";

export async function POST(req: NextRequest) {
  try {
    const { name, email, password } = await req.json();
    
    // Check if user already exists
    const existingUser = await prisma.user.findUnique({
      where: { email },
    });
    
    if (existingUser) {
      return NextResponse.json(
        { success: false, message: "Email already in use" },
        { status: 400 }
      );
    }
    
    // Generate verification token
    const verificationToken = generateVerificationToken(email);
    const tokenExpiry = new Date();
    tokenExpiry.setHours(tokenExpiry.getHours() + 24); // Token valid for 24 hours
    
    // Hash the password with bcryptjs
    const hashedPassword = await bcrypt.hash(password, 10);
    
    // Create user with verification token
    const user = await prisma.user.create({
      data: {
        name,
        email,
        password: hashedPassword,
        emailVerificationToken: verificationToken,
        emailVerificationExpires: tokenExpiry,
      },
    });
    
    // Send verification email
    await sendVerificationEmail(email, verificationToken);
    
    return NextResponse.json(
      { success: true, message: "Registration successful. Please verify your email." },
      { status: 201 }
    );
  } catch (error) {
    console.error("Registration error:", error);
    return NextResponse.json(
      { success: false, message: "Registration failed" },
      { status: 500 }
    );
  }
} 