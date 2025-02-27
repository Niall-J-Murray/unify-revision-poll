import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/app/api/auth/[...nextauth]/route";
import { prisma } from "@/lib/prisma";

export async function POST(
  req: NextRequest,
  context: { params: { id: string } }
) {
  try {
    const session = await getServerSession(authOptions);
    
    if (!session || !session.user) {
      return NextResponse.json(
        { success: false, message: "Unauthorized" },
        { status: 401 }
      );
    }
    
    // Await the params before using them
    const { id: featureRequestId } = await context.params;
    
    // Check if feature request exists
    const featureRequest = await prisma.featureRequest.findUnique({
      where: { id: featureRequestId },
    });
    
    if (!featureRequest) {
      return NextResponse.json(
        { success: false, message: "Feature request not found" },
        { status: 404 }
      );
    }
    
    // Block users from voting on their own requests
    if (featureRequest.userId === session.user.id) {
      return NextResponse.json(
        { success: false, message: "You cannot vote on your own request" },
        { status: 403 }
      );
    }
    
    // Check if user has already voted
    const existingVote = await prisma.vote.findUnique({
      where: {
        userId_featureRequestId: {
          userId: session.user.id,
          featureRequestId,
        },
      },
    });
    
    if (existingVote) {
      // Remove vote
      await prisma.vote.delete({
        where: { id: existingVote.id },
      });

      // Create an activity for removing the vote
      await prisma.activity.create({
        data: {
          type: 'unvoted',
          userId: session.user.id,
          featureRequestId,
        },
      });
      
      return NextResponse.json({
        success: true,
        message: "Vote removed",
        action: "removed",
      });
    } else {
      // Create new vote
      const vote = await prisma.vote.create({
        data: {
          userId: session.user.id,
          featureRequestId,
        },
      });
      
      // Create an activity for the vote
      await prisma.activity.create({
        data: {
          type: 'voted',
          userId: session.user.id,
          featureRequestId,
        },
      });
      
      return NextResponse.json({
        success: true,
        message: "Vote added",
        action: "added",
      });
    }
  } catch (error) {
    console.error("Vote error:", error);
    return NextResponse.json(
      { success: false, message: "Failed to process vote" },
      { status: 500 }
    );
  }
} 