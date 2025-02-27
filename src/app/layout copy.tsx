import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";
import { AuthProvider, AuthContextProvider } from "@/context/auth-provider";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title: "Authentication App",
  description: "A simple authentication app with NextAuth and Prisma",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className={inter.className}>
        <AuthProvider>
          <AuthContextProvider>{children}</AuthContextProvider>
        </AuthProvider>
      </body>
    </html>
  );
}
