import { useSession } from "next-auth/react";
import { useRouter } from "next/navigation";
import { useEffect } from "react";

type Role = "USER" | "ADMIN" | "EDITOR";

export function useAuthorization(requiredRole?: Role) {
  const { data: session, status } = useSession();
  const router = useRouter();
  
  useEffect(() => {
    // If not authenticated, redirect to login
    if (status === "unauthenticated") {
      router.push("/login");
      return;
    }
    
    // If authenticated but role check is required
    if (status === "authenticated" && requiredRole) {
      const userRole = session?.user?.role || "USER";
      
      // If user doesn't have the required role
      if (userRole !== requiredRole && userRole !== "ADMIN") {
        router.push("/unauthorized");
      }
    }
  }, [status, session, requiredRole, router]);
  
  return {
    isAuthenticated: status === "authenticated",
    isLoading: status === "loading",
    user: session?.user,
    hasRole: (role: Role) => {
      const userRole = session?.user?.role || "USER";
      return userRole === role || userRole === "ADMIN";
    },
  };
} 