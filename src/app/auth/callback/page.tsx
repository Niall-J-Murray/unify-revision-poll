"use client";

import { useEffect } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Loading from "@/app/components/ui/loading";

export default function AuthCallback() {
  const router = useRouter();
  const searchParams = useSearchParams();

  useEffect(() => {
    // Process the authentication response
    const handleAuthResponse = async () => {
      try {
        // Extract tokens from URL hash
        const hash = window.location.hash.substring(1);
        const params = new URLSearchParams(hash);
        
        // Get access token and other params
        const accessToken = params.get("access_token");
        const refreshToken = params.get("refresh_token");
        const type = params.get("type");
        
        if (accessToken) {
          // Store tokens securely (consider using cookies or secure storage)
          // For example purposes only - in production use secure methods
          sessionStorage.setItem("access_token", accessToken);
          
          // Redirect based on auth type
          if (type === "signup") {
            router.push("/dashboard?welcome=true");
          } else {
            router.push("/dashboard");
          }
        } else {
          // Handle error case
          router.push("/login?error=Authentication failed");
        }
      } catch (error) {
        console.error("Auth callback error:", error);
        router.push("/login?error=Authentication failed");
      }
    };

    handleAuthResponse();
  }, [router]);

  return <Loading message="Completing authentication..." />;
} 