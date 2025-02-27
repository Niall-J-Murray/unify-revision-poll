import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/app/api/auth/[...nextauth]/route";
import { prisma } from "@/lib/prisma";

// PUT handler for editing
export async function PUT(
  req: NextRequest,
  context: { params: { id: string } }
) {
  try {
    const session = await getServerSession(authOptions);
    
    if (!session?.user) {
      return NextResponse.json(
        { message: "Unauthorized" },
        { status: 401 }
      );
    }

    const featureRequestId = context.params.id;
    const { title, description } = await req.json();

    // Check if the feature request exists and belongs to the user
    const existingRequest = await prisma.featureRequest.findUnique({
      where: { id: featureRequestId },
      include: { votes: true },
    });

    if (!existingRequest) {
      return NextResponse.json(
        { message: "Feature request not found" },
        { status: 404 }
      );
    }

    if (existingRequest.userId !== session.user.id) {
      return NextResponse.json(
        { message: "You can only edit your own requests" },
        { status: 403 }
      );
    }

    if (existingRequest.votes.length > 0) {
      return NextResponse.json(
        { message: "Cannot edit a request that has votes" },
        { status: 403 }
      );
    }

    // Update the feature request
    const updatedRequest = await prisma.featureRequest.update({
      where: { id: featureRequestId },
      data: { title, description },
      include: {
        user: {
          select: {
            name: true,
            email: true,
          },
        },
        votes: {
          select: {
            userId: true,
          },
        },
      },
    });

    // Create an activity for the edit
    await prisma.activity.create({
      data: {
        type: 'edited',
        userId: session.user.id,
        featureRequestId,
      },
    });

    return NextResponse.json(updatedRequest);
  } catch (error) {
    console.error("Edit feature request error:", error);
    return NextResponse.json(
      { message: "Failed to edit feature request" },
      { status: 500 }
    );
  }
}

export async function DELETE(
  req: NextRequest,
  context: { params: { id: string } }
) {
  try {
    const session = await getServerSession(authOptions);
    
    if (!session?.user) {
      return NextResponse.json(
        { message: "Unauthorized" },
        { status: 401 }
      );
    }

    const { id: featureRequestId } = await context.params;

    // Check if the feature request exists
    const featureRequest = await prisma.featureRequest.findUnique({
      where: { id: featureRequestId },
      include: {
        votes: true,
        activities: true,
      },
    });

    if (!featureRequest) {
      return NextResponse.json(
        { message: "Feature request not found" },
        { status: 404 }
      );
    }

    // Check if the user is the owner of the request
    if (featureRequest.userId !== session.user.id) {
      return NextResponse.json(
        { message: "You can only delete your own requests" },
        { status: 403 }
      );
    }

    // Check if there are any votes
    if (featureRequest.votes.length > 0) {
      return NextResponse.json(
        { message: "Cannot delete a request that has votes" },
        { status: 403 }
      );
    }

    // Create an activity for the deletion with the request title
    await prisma.activity.create({
      data: {
        type: 'deleted',
        userId: session.user.id,
        deletedRequestTitle: featureRequest.title,
      },
    });

    // Delete in the correct order to handle foreign key constraints
    await prisma.$transaction(async (tx) => {
      // First delete all other activities related to this feature request
      await tx.activity.deleteMany({
        where: { 
          featureRequestId,
          type: { not: 'deleted' }
        },
      });

      // Then delete the feature request
      await tx.featureRequest.delete({
        where: { id: featureRequestId },
      });
    });

    return NextResponse.json({ message: "Feature request deleted successfully" });
  } catch (error) {
    console.error("Delete feature request error:", error);
    return NextResponse.json(
      { message: "Failed to delete feature request" },
      { status: 500 }
    );
  }
} 