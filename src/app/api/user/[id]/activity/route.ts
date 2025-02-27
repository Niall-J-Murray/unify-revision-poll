import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/app/api/auth/[...nextauth]/route";
import { prisma } from "@/lib/prisma";

export async function GET(
  req: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    const session = await getServerSession(authOptions);
    const url = new URL(req.url);
    const id = url.pathname.split('/')[3]; // Get id from URL path
    
    if (!session?.user) {
      return NextResponse.json(
        { message: "Unauthorized" },
        { status: 401 }
      );
    }

    // Only allow users to view their own activity
    if (session.user.id !== id) {
      return NextResponse.json(
        { message: "You can only view your own activity" },
        { status: 403 }
      );
    }

    const activities = await prisma.activity.findMany({
      where: {
        userId: id,
      },
      include: {
        featureRequest: {
          select: {
            title: true,
          },
        },
      },
      orderBy: {
        createdAt: 'desc',
      },
      take: 10, // Limit to last 10 activities
    });

    // Map the activities to handle deleted requests
    const mappedActivities = activities.map(activity => ({
      ...activity,
      featureRequest: activity.type === 'deleted' 
        ? { title: activity.deletedRequestTitle }
        : activity.featureRequest,
    }));

    return NextResponse.json(mappedActivities);
  } catch (error) {
    console.error("Error fetching user activity:", error);
    return NextResponse.json(
      { message: "Failed to fetch activity" },
      { status: 500 }
    );
  }
} 