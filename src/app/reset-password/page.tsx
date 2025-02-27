"use client";

import { useState, useEffect } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Link from "next/link";
import Input from "@/app/components/ui/input";
import AuthLayout from "@/app/components/auth-layout";

export default function ResetPassword() {
  const searchParams = useSearchParams();
  const router = useRouter();
  const [formData, setFormData] = useState({
    password: "",
    confirmPassword: "",
  });
  const [token, setToken] = useState("");
  const [loading, setLoading] = useState(false);
  const [success, setSuccess] = useState(false);
  const [error, setError] = useState("");
  const [tokenValid, setTokenValid] = useState(true);

  useEffect(() => {
    const tokenParam = searchParams.get("token");
    if (!tokenParam) {
      setTokenValid(false);
      setError("Invalid or missing reset token");
      return;
    }
    setToken(tokenParam);

    // Verify token validity
    const verifyToken = async () => {
      try {
        const response = await fetch(`/api/auth/verify-reset-token?token=${tokenParam}`);
        const data = await response.json();

        if (!response.ok || !data.valid) {
          setTokenValid(false);
          setError(data.message || "Invalid or expired reset token");
        }
      } catch (err) {
        setTokenValid(false);
        setError("Failed to verify reset token");
      }
    };

    verifyToken();
  }, [searchParams]);

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const { name, value } = e.target;
    setFormData((prev) => ({ ...prev, [name]: value }));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setLoading(true);

    // Validate passwords match
    if (formData.password !== formData.confirmPassword) {
      setError("Passwords do not match");
      setLoading(false);
      return;
    }

    try {
      const response = await fetch("/api/auth/reset-password", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          token,
          password: formData.password,
        }),
      });

      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.message || "Failed to reset password");
      }

      setSuccess(true);
      setTimeout(() => {
        router.push("/login?reset=true");
      }, 2000);
    } catch (err: any) {
      setError(err.message || "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  return (
    <AuthLayout 
      title="Reset your password" 
      subtitle="Create a new password for your account"
    >
      {error && (
        <div className="mb-4 p-3 bg-red-50 text-red-700 rounded-lg border border-red-200 text-sm">
          {error}
        </div>
      )}

      {success && (
        <div className="mb-4 p-3 bg-green-50 text-green-700 rounded-lg border border-green-200 text-sm">
          Password reset successful! Redirecting to login...
        </div>
      )}

      {!tokenValid ? (
        <div className="text-center">
          <p className="text-gray-700 mb-4">
            The password reset link is invalid or has expired. Please request a new one.
          </p>
          <Link
            href="/forgot-password"
            className="inline-block px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors"
          >
            Request New Link
          </Link>
        </div>
      ) : (
        !success && (
          <form onSubmit={handleSubmit} className="space-y-4">
            <Input
              id="password"
              name="password"
              type="password"
              label="New password"
              value={formData.password}
              onChange={handleChange}
              required
            />

            <Input
              id="confirmPassword"
              name="confirmPassword"
              type="password"
              label="Confirm new password"
              value={formData.confirmPassword}
              onChange={handleChange}
              required
            />

            <div className="mt-1">
              <p className="text-xs text-gray-500">
                Password must be at least 8 characters and include a number and a
                special character.
              </p>
            </div>

            <button
              type="submit"
              disabled={loading}
              className="w-full flex justify-center py-2.5 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              {loading ? "Resetting..." : "Reset Password"}
            </button>
          </form>
        )
      )}
    </AuthLayout>
  );
} 