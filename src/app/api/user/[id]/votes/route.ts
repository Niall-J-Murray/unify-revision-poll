import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";

export async function GET(req: NextRequest, context: { params: { id: string } }) {
  const { id: userId } = await context.params;

  try {
    const voteCount = await prisma.vote.count({
      where: { userId: userId },
    });

    return NextResponse.json({ count: voteCount });
  } catch (error) {
    console.error("Error fetching vote count:", error);
    return NextResponse.json({ message: "Failed to fetch votes" }, { status: 500 });
  }
} 