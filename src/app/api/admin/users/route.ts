import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getServerSession } from "next-auth/next";
import { authOptions } from "../../auth/[...nextauth]/route";

export async function GET(req: NextRequest) {
  try {
    // Check if user is authenticated and has admin role
    const session = await getServerSession(authOptions);
    
    if (!session || session.user.role !== "ADMIN") {
      return NextResponse.json(
        { success: false, message: "Unauthorized" },
        { status: 403 }
      );
    }
    
    // Fetch all users
    const users = await prisma.user.findMany({
      select: {
        id: true,
        name: true,
        email: true,
        emailVerified: true,
        role: true,
        createdAt: true,
      },
      orderBy: {
        createdAt: "desc",
      },
    });
    
    return NextResponse.json({ success: true, users });
  } catch (error) {
    console.error("Admin users fetch error:", error);
    return NextResponse.json(
      { success: false, message: "Failed to fetch users" },
      { status: 500 }
    );
  }
}

// Add user
export async function POST(req: NextRequest) {
  try {
    // Check if user is authenticated and has admin role
    const session = await getServerSession(authOptions);
    
    if (!session || session.user.role !== "ADMIN") {
      return NextResponse.json(
        { success: false, message: "Unauthorized" },
        { status: 403 }
      );
    }
    
    const { name, email, password, role } = await req.json();
    
    // Validate input
    if (!email || !password) {
      return NextResponse.json(
        { success: false, message: "Email and password are required" },
        { status: 400 }
      );
    }
    
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
    
    // Create user
    const user = await prisma.user.create({
      data: {
        name,
        email,
        password, // Password should be hashed before this point
        role: role || "USER",
        emailVerified: new Date(), // Admin-created users are auto-verified
      },
    });
    
    return NextResponse.json(
      { 
        success: true, 
        message: "User created successfully",
        user: {
          id: user.id,
          name: user.name,
          email: user.email,
          role: user.role,
        }
      },
      { status: 201 }
    );
  } catch (error) {
    console.error("Admin user creation error:", error);
    return NextResponse.json(
      { success: false, message: "Failed to create user" },
      { status: 500 }
    );
  }
} 