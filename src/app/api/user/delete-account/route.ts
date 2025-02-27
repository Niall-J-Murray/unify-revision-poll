import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/app/api/auth/[...nextauth]/route";
import { prisma } from "@/lib/prisma";
import bcrypt from "bcryptjs";

export async function POST(req: NextRequest) {
  try {
    const session = await getServerSession(authOptions);
    
    if (!session || !session.user) {
      return NextResponse.json(
        { success: false, message: "Unauthorized" },
        { status: 401 }
      );
    }
    
    const { password } = await req.json();
    
    if (!password) {
      return NextResponse.json(
        { success: false, message: "Password is required" },
        { status: 400 }
      );
    }
    
    // Get user with password
    const user = await prisma.user.findUnique({
      where: { email: session.user.email as string },
      select: {
        id: true,
        password: true,
      },
    });
    
    if (!user || !user.password) {
      return NextResponse.json(
        { success: false, message: "User not found or no password set" },
        { status: 404 }
      );
    }
    
    // Verify password
    const isPasswordValid = await bcrypt.compare(password, user.password);
    
    if (!isPasswordValid) {
      return NextResponse.json(
        { success: false, message: "Password is incorrect" },
        { status: 400 }
      );
    }
    
    // Delete user
    await prisma.user.delete({
      where: { id: user.id },
    });
    
    return NextResponse.json({
      success: true,
      message: "Account deleted successfully",
    });
  } catch (error) {
    console.error("Account deletion error:", error);
    return NextResponse.json(
      { success: false, message: "Failed to delete account" },
      { status: 500 }
    );
  }
} 