import NextAuth from "next-auth";
import { PrismaAdapter } from "@auth/prisma-adapter";
import { prisma } from "@/lib/prisma";
import CredentialsProvider from "next-auth/providers/credentials";
// import GoogleProvider from "next-auth/providers/google";
// import GitHubProvider from "next-auth/providers/github";
import bcrypt from "bcryptjs";

export const authOptions = {
  adapter: PrismaAdapter(prisma),
  providers: [
    CredentialsProvider({
      name: "Credentials",
      credentials: {
        email: { label: "Email", type: "email" },
        password: { label: "Password", type: "password" }
      },
      async authorize(credentials) {
        if (!credentials?.email || !credentials?.password) {
          return null;
        }

        try {
          // Find the user by email
          const user = await prisma.user.findUnique({
            where: { email: credentials.email }
          });

          // If no user found or no password (social login user)
          if (!user || !user.password) {
            console.log("User not found or no password");
            return null;
          }

          // Check if email is verified
          if (!user.emailVerified) {
            throw new Error("Please verify your email before logging in");
          }

          // Compare passwords
          const isPasswordValid = await bcrypt.compare(
            credentials.password,
            user.password
          );

          console.log("Attempting login for:", credentials.email);
          console.log("Password comparison result:", isPasswordValid);

          console.log("User found:", !!user);
          console.log("Email verified:", !!user?.emailVerified);
          console.log("Password in DB:", user?.password?.substring(0, 10) + "...");
          console.log("Password from credentials:", credentials.password);

          if (!isPasswordValid) {
            console.log("Invalid password");
            return null;
          }

          // Return user data
          return {
            id: user.id,
            email: user.email,
            name: user.name,
            role: user.role,
          };
        } catch (error) {
          console.error("Auth error:", error);
          throw error;
        }
      }
    }),
    // GoogleProvider({
    //   clientId: process.env.GOOGLE_CLIENT_ID!,
    //   clientSecret: process.env.GOOGLE_CLIENT_SECRET!,
    // }),
    // GitHubProvider({
    //   clientId: process.env.GITHUB_ID!,
    //   clientSecret: process.env.GITHUB_SECRET!,
    // }),
  ],
  session: {
    strategy: "jwt",
  },
  callbacks: {
    async jwt({ token, user }) {
      if (user) {
        token.id = user.id;
        token.role = user.role;
      }
      return token;
    },
    async session({ session, token }) {
      if (session.user) {
        session.user.id = token.id;
        session.user.role = token.role;
      }
      return session;
    },
    async redirect({ url, baseUrl }) {
      // Handle Supabase auth redirects
      if (url.startsWith('/auth/callback')) {
        return url;
      }
      // Default NextAuth behavior
      return baseUrl;
    },
  },
  pages: {
    signIn: "/login",
    error: "/login",
  },
  secret: process.env.NEXTAUTH_SECRET,
  debug: process.env.NODE_ENV === "development",
};

const handler = NextAuth(authOptions);
export { handler as GET, handler as POST };