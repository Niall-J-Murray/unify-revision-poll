"use client";

import { useState, useEffect } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Link from "next/link";
import { signIn } from "next-auth/react";
import Input from "@/app/components/ui/input";
import { FaGoogle, FaGithub } from "react-icons/fa";
import AuthLayout from "@/app/components/auth-layout";
import { FiMail } from "react-icons/fi";

export default function Login() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [formData, setFormData] = useState({
    email: "",
    password: "",
  });
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [success, setSuccess] = useState(false);
  const [message, setMessage] = useState("");
  const [rateLimited, setRateLimited] = useState(false);
  const [remainingAttempts, setRemainingAttempts] = useState<number | null>(
    null
  );

  // Check for query parameters
  useEffect(() => {
    const registered = searchParams.get("registered");
    const verified = searchParams.get("verified");
    const reset = searchParams.get("reset");
    const deleted = searchParams.get("deleted");
    const error = searchParams.get("error");

    if (registered) {
      setMessage(
        "Registration successful! Please check your email to verify your account."
      );
    } else if (verified) {
      setMessage("Email verified successfully! You can now log in.");
      // Clear any previous errors when coming from verification
      setError("");
    } else if (reset) {
      setMessage(
        "Password reset successfully! You can now log in with your new password."
      );
    } else if (deleted) {
      setMessage("Your account has been successfully deleted.");
    } else if (error) {
      setError(
        error === "CredentialsSignin"
          ? "Invalid email or password"
          : "An error occurred during sign in"
      );
    }
  }, [searchParams]);

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const { name, value } = e.target;
    setFormData((prev) => ({ ...prev, [name]: value }));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setLoading(true);

    try {
      const result = await signIn("credentials", {
        redirect: false,
        email: formData.email,
        password: formData.password,
      });

      if (result?.error) {
        if (result.error.includes("attempts remaining")) {
          // Extract remaining attempts from error message
          const match = result.error.match(/(\d+) attempts remaining/);
          if (match && match[1]) {
            setRemainingAttempts(parseInt(match[1]));
          }
          setError(result.error);
        } else if (result.error === "Too many requests") {
          setRateLimited(true);
        } else {
          setError(result.error);
        }
      } else {
        setSuccess(true);
        setTimeout(() => {
          router.push("/dashboard");
        }, 1500);
      }
    } catch (err) {
      setError("An unexpected error occurred");
    } finally {
      setLoading(false);
    }
  };

  return (
    <AuthLayout
      title="Welcome back"
      subtitle="Sign in to your account to continue"
    >
      {error && (
        <div className="mb-4 p-3 bg-red-50 dark:bg-red-900/20 text-red-700 dark:text-red-400 rounded-lg border border-red-200 dark:border-red-800/30 text-sm">
          {error}
        </div>
      )}

      {message && !error && (
        <div className="mb-4 p-3 bg-green-50 dark:bg-green-900/20 text-green-700 dark:text-green-400 rounded-lg border border-green-200 dark:border-green-800/30">
          <p className="mb-2">{message}</p>
          {searchParams.get("registered") === "true" && (
            <a
              href="mailto:"
              className="inline-flex items-center text-sm text-green-700 dark:text-green-300 hover:underline"
            >
              <FiMail className="mr-1.5 h-4 w-4" />
              Open Email Client
            </a>
          )}
        </div>
      )}

      {success && (
        <div className="mb-4 p-3 bg-green-50 dark:bg-green-900/20 text-green-700 dark:text-green-400 rounded-lg border border-green-200 dark:border-green-800/30 text-sm">
          Login successful! Redirecting...
        </div>
      )}

      {rateLimited ? (
        <div className="text-center py-8">
          <div className="text-red-600 dark:text-red-400 mb-4">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              className="h-12 w-12 mx-auto"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
              />
            </svg>
          </div>
          <h3 className="text-xl font-bold mb-2">Too Many Login Attempts</h3>
          <p className="text-github-secondary dark:text-github-dark-secondary mb-4">
            Your account has been temporarily locked due to multiple failed
            login attempts. Please try again later or reset your password.
          </p>
          <Link
            href="/forgot-password"
            className="text-github-primary dark:text-github-dark-primary hover:underline"
          >
            Reset your password
          </Link>
        </div>
      ) : (
        !success && (
          <form onSubmit={handleSubmit} className="space-y-4">
            <Input
              id="email"
              name="email"
              type="email"
              label="Email address"
              value={formData.email}
              onChange={handleChange}
              required
            />

            <Input
              id="password"
              name="password"
              type="password"
              label="Password"
              value={formData.password}
              onChange={handleChange}
              required
            />

            <div className="flex items-center justify-between">
              <div className="flex items-center">
                <input
                  id="remember-me"
                  name="remember-me"
                  type="checkbox"
                  className="h-4 w-4 text-github-primary dark:text-github-dark-primary focus:ring-github-primary dark:focus:ring-github-dark-primary border-github-border dark:border-github-dark-border rounded"
                />
                <label htmlFor="remember-me" className="ml-2 block text-sm">
                  Remember me
                </label>
              </div>

              <Link
                href="/forgot-password"
                className="text-sm font-medium text-github-primary dark:text-github-dark-primary hover:text-opacity-90"
              >
                Forgot password?
              </Link>
            </div>

            <button
              type="submit"
              disabled={loading}
              className="w-full flex justify-center py-2.5 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-github-primary dark:bg-github-dark-accent hover:bg-opacity-90 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-github-primary dark:focus:ring-github-dark-primary disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              {loading ? "Signing in..." : "Sign in"}
            </button>

            <div className="mt-6">
              <div className="relative">
                <div className="absolute inset-0 flex items-center">
                  <div className="w-full border-t border-github-border dark:border-github-dark-border"></div>
                </div>
                <div className="relative flex justify-center text-sm">
                  <span className="px-2 bg-github-bg dark:bg-github-dark-hover text-github-secondary dark:text-github-dark-secondary">
                    Or continue with
                  </span>
                </div>
              </div>

              <div className="mt-6 grid grid-cols-2 gap-3">
                <button
                  type="button"
                  className="w-full inline-flex justify-center py-2.5 px-4 border border-github-border dark:border-github-dark-border rounded-md shadow-sm bg-github-bg dark:bg-github-dark-bg text-sm font-medium text-github-fg dark:text-github-dark-fg hover:bg-github-hover dark:hover:bg-github-dark-hover"
                  onClick={() =>
                    signIn("google", {
                      callbackUrl: "/dashboard",
                      prompt: "select_account",
                    })
                  }
                >
                  <FaGoogle className="h-5 w-5 text-red-500" />
                  <span className="ml-2">Google</span>
                </button>
                <button
                  type="button"
                  className="w-full inline-flex justify-center py-2.5 px-4 border border-github-border dark:border-github-dark-border rounded-md shadow-sm bg-github-bg dark:bg-github-dark-bg text-sm font-medium text-github-fg dark:text-github-dark-fg hover:bg-github-hover dark:hover:bg-github-dark-hover"
                  onClick={() =>
                    signIn("github", {
                      callbackUrl: "/dashboard",
                      prompt: "consent",
                    })
                  }
                >
                  <FaGithub className="h-5 w-5" />
                  <span className="ml-2">GitHub</span>
                </button>
              </div>
            </div>

            <div className="mt-6 text-center">
              <p className="text-sm text-github-secondary dark:text-github-dark-secondary">
                Don't have an account?{" "}
                <Link
                  href="/register"
                  className="font-medium text-github-primary dark:text-github-dark-primary hover:text-opacity-90"
                >
                  Sign up
                </Link>
              </p>
            </div>
          </form>
        )
      )}
    </AuthLayout>
  );
}
