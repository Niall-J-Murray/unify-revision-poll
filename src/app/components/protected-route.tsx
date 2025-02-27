"use client";

import { useSession } from "next-auth/react";
import { useRouter } from "next/navigation";
import { useEffect, ReactNode } from "react";
import Loading from "@/app/components/ui/loading";

type ProtectedRouteProps = {
  children: ReactNode;
  requiredRole?: string;
};

export default function ProtectedRoute({ 
  children, 
  requiredRole 
}: ProtectedRouteProps) {
  const { data: session, status } = useSession();
  const router = useRouter();

  useEffect(() => {
    if (status === "unauthenticated") {
      router.push("/login");
      return;
    }

    if (status === "authenticated" && requiredRole) {
      if (session.user.role !== requiredRole) {
        router.push("/dashboard");
      }
    }
  }, [status, session, router, requiredRole]);

  if (status === "loading") {
    return <Loading message="Checking authentication..." />;
  }

  if (status === "authenticated") {
    if (requiredRole && session.user.role !== requiredRole) {
      return null; // Will redirect in useEffect
    }
    return <>{children}</>;
  }

  return null; // Will redirect in useEffect
}
