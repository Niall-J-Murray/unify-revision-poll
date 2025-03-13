import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { createHash, randomBytes } from "crypto";
import { sendPasswordResetEmail } from "@/lib/email";

export async function POST(req: NextRequest) {
  try {
    const { email } = await req.json();

    // Handle missing email case
    if (!email) {
      return NextResponse.json(
        {
          success: true,
          message:
            "If your email is registered, you will receive a password reset link.",
        },
        { status: 200 }
      );
    }

    // Check if user exists
    const user = await prisma.user.findUnique({
      where: { email },
    });

    if (!user) {
      // Don't reveal that the user doesn't exist
      return NextResponse.json(
        {
          success: true,
          message:
            "If your email is registered, you will receive a password reset link.",
        },
        { status: 200 }
      );
    }

    // Generate reset token
    const resetToken = randomBytes(32).toString("hex");
    const hashedToken = createHash("sha256").update(resetToken).digest("hex");

    const tokenExpiry = new Date();
    tokenExpiry.setHours(tokenExpiry.getHours() + 1); // Token valid for 1 hour

    // Save token to user
    await prisma.user.update({
      where: { id: user.id },
      data: {
        resetPasswordToken: hashedToken,
        resetPasswordExpires: tokenExpiry,
      },
    });

    // Send password reset email
    await sendPasswordResetEmail(email, resetToken);

    return NextResponse.json(
      { success: true, message: "Password reset email sent" },
      { status: 200 }
    );
  } catch (error) {
    console.error("Forgot password error:", error);
    if (error instanceof Error && error.message === "Invalid JSON") {
      return NextResponse.json(
        { success: false, message: "Failed to process request" },
        { status: 500 }
      );
    } else {
      return NextResponse.json(
        { success: false, message: "Failed to process request" },
        { status: 500 }
      );
    }
  }
}
