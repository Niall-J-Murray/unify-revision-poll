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
    
    // Use a transaction to ensure all operations succeed or fail together
    await prisma.$transaction(async (tx) => {
      // 1. Find all feature requests created by this user
      const userFeatureRequests = await tx.featureRequest.findMany({
        where: { userId: user.id },
        include: {
          _count: {
            select: { votes: true }
          }
        }
      });
      
      // 2. Delete feature requests with fewer than 2 votes
      const featureRequestsToDelete = userFeatureRequests
        .filter(fr => fr._count.votes < 2)
        .map(fr => fr.id);
      
      // 3. For feature requests to keep (2+ votes), we'll create a system user if needed
      // and transfer ownership to maintain referential integrity
      const systemUser = await getOrCreateSystemUser(tx);
      
      // Transfer ownership of popular feature requests to the system user
      const featureRequestsToKeep = userFeatureRequests
        .filter(fr => fr._count.votes >= 2)
        .map(fr => fr.id);
        
      if (featureRequestsToKeep.length > 0) {
        await tx.featureRequest.updateMany({
          where: {
            id: { in: featureRequestsToKeep }
          },
          data: {
            userId: systemUser.id,
            description: tx.raw("description || ' (Creator account deleted)'")
          }
        });
      }
      
      // Now delete the low-vote feature requests
      await tx.featureRequest.deleteMany({
        where: {
          id: { in: featureRequestsToDelete }
        }
      });
      
      // 4. Find all votes cast by this user
      const userVotes = await tx.vote.findMany({
        where: { userId: user.id },
        include: {
          featureRequest: {
            include: {
              _count: {
                select: { votes: true }
              }
            }
          }
        }
      });
      
      // 5. Delete votes where the feature request has fewer than 3 total votes
      const votesToDelete = userVotes
        .filter(vote => vote.featureRequest._count.votes < 3)
        .map(vote => vote.id);
        
      // 6. For votes that will remain (on features with 3+ votes), transfer to system user
      const votesToKeep = userVotes
        .filter(vote => vote.featureRequest._count.votes >= 3)
        .map(vote => vote.id);
        
      if (votesToKeep.length > 0) {
        await tx.vote.updateMany({
          where: {
            id: { in: votesToKeep }
          },
          data: {
            userId: systemUser.id
          }
        });
      }
      
      // Now delete the low-vote votes
      await tx.vote.deleteMany({
        where: {
          id: { in: votesToDelete }
        }
      });
      
      // 7. Delete activities related to this user
      await tx.activity.deleteMany({
        where: { userId: user.id },
      });
      
      // 8. Finally delete the user
      await tx.user.delete({
        where: { id: user.id },
      });
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

// Helper function to get or create a system user for transferred content
async function getOrCreateSystemUser(prisma: any) {
  const systemEmail = "system@unify-poll.com";
  
  // Try to find the system user
  let systemUser = await prisma.user.findUnique({
    where: { email: systemEmail }
  });
  
  // If it doesn't exist, create it
  if (!systemUser) {
    systemUser = await prisma.user.create({
      data: {
        email: systemEmail,
        name: "System (Deleted User Content)",
        role: "SYSTEM"
      }
    });
  }
  
  return systemUser;
} 