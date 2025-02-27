import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth/next";
import { authOptions } from "@/app/api/auth/[...nextauth]/route";
import { prisma } from "@/lib/prisma";

// Get all feature requests
export async function GET(req: NextRequest) {
  try {
    const session = await getServerSession(authOptions);
    const searchParams = req.nextUrl.searchParams;
    const status = searchParams.get("status");
    const view = searchParams.get("view");
    const sort = searchParams.get("sort") || "votes";

    const where: any = {};
    
    // Only filter status if not "ALL"
    if (status && status !== "ALL") {
      if (status === "OPEN") {
        // For "Open", exclude completed and in-progress
        where.status = { notIn: ["COMPLETED", "IN_PROGRESS", "REJECTED"] };
      } else {
        // For other statuses, filter exactly
        where.status = status;
      }
    }

    // Apply view filter if user is logged in
    if (session?.user && view !== "ALL") {
      if (view === "MINE") {
        where.userId = session.user.id;
      } else if (view === "VOTED") {
        where.votes = {
          some: {
            userId: session.user.id
          }
        };
      }
    }

    const featureRequests = await prisma.featureRequest.findMany({
      where,
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
      orderBy: sort === "votes" 
        ? { votes: { _count: 'desc' } }
        : sort === "newest"
        ? { createdAt: 'desc' }
        : { createdAt: 'asc' },
    });

    return NextResponse.json({
      success: true,
      featureRequests: featureRequests.map(request => ({
        ...request,
        voteCount: request.votes.length,
      })),
    });
  } catch (error) {
    console.error("Feature requests fetch error:", error);
    return NextResponse.json(
      { success: false, message: "Failed to fetch feature requests" },
      { status: 500 }
    );
  }
}

// Create new feature request
export async function POST(req: NextRequest) {
  try {
    const session = await getServerSession(authOptions);
    if (!session?.user) {
      return NextResponse.json({ message: "Unauthorized" }, { status: 401 });
    }

    const data = await req.json();
    const { title, description } = data;

    // Validate input
    if (!title || !description) {
      return NextResponse.json(
        { success: false, message: "Title and description are required" },
        { status: 400 }
      );
    }
    
    if (title.length > 100) {
      return NextResponse.json(
        { success: false, message: "Title must be 100 characters or less" },
        { status: 400 }
      );
    }
    
    if (description.length > 500) {
      return NextResponse.json(
        { success: false, message: "Description must be 500 characters or less" },
        { status: 400 }
      );
    }

    // Create the feature request
    const featureRequest = await prisma.featureRequest.create({
      data: {
        title,
        description,
        userId: session.user.id,
      },
    });

    // Create an activity for the new feature request
    await prisma.activity.create({
      data: {
        type: 'created',
        userId: session.user.id,
        featureRequestId: featureRequest.id,
      },
    });

    return NextResponse.json(featureRequest);
  } catch (error) {
    console.error("Create feature request error:", error);
    return NextResponse.json(
      { message: "Failed to create feature request" },
      { status: 500 }
    );
  }
} 