import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";

export async function GET(req: NextRequest, context: { params: { id: string } }) {
  const { id: userId } = await context.params;

  try {
    const count = await prisma.featureRequest.count({
      where: { userId: userId },
    });

    return NextResponse.json({ count });
  } catch (error) {
    console.error("Error fetching feature request count:", error);
    return NextResponse.json({ message: "Failed to fetch feature request count" }, { status: 500 });
  }
} 