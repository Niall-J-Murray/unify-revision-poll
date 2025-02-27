"use client";

import Link from "next/link";
import { useSession } from "next-auth/react";
import { useTheme } from "@/context/theme-context";
import {
  FiMoon,
  FiSun,
  FiCheckCircle,
  FiUsers,
  FiTrendingUp,
} from "react-icons/fi";

export default function Home() {
  const { status } = useSession();
  const isAuthenticated = status === "authenticated";
  const { theme, toggleTheme } = useTheme();

  return (
    <div className="min-h-screen bg-github-bg dark:bg-github-dark-bg text-github-fg dark:text-github-dark-fg">
      {/* Header */}
      <header className="bg-github-bg dark:bg-github-dark-bg border-b border-github-border dark:border-github-dark-border">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-6">
            <div className="flex items-center">
              <h1 className="text-2xl font-bold text-github-primary dark:text-github-dark-primary">
                Unify Poll
              </h1>
            </div>
            <div className="flex items-center space-x-4">
              <button
                onClick={toggleTheme}
                className="p-2 rounded-md hover:bg-github-hover dark:hover:bg-github-dark-hover"
                aria-label="Toggle theme"
              >
                {theme === "dark" ? (
                  <FiSun className="h-5 w-5" />
                ) : (
                  <FiMoon className="h-5 w-5" />
                )}
              </button>

              {isAuthenticated ? (
                <Link
                  href="/dashboard"
                  className="px-4 py-2 border border-github-border dark:border-github-dark-border rounded-md text-sm font-medium hover:bg-github-hover dark:hover:bg-github-dark-hover transition-colors"
                >
                  Dashboard
                </Link>
              ) : (
                <>
                  <Link
                    href="/api/auth/signin"
                    className="px-4 py-2 border border-github-border dark:border-github-dark-border rounded-md text-sm font-medium hover:bg-github-hover dark:hover:bg-github-dark-hover transition-colors"
                  >
                    Sign in
                  </Link>
                  <Link
                    href="/register"
                    className="px-4 py-2 bg-github-primary dark:bg-github-dark-accent border border-transparent rounded-md text-sm font-medium text-white hover:bg-opacity-90 transition-colors"
                  >
                    Register
                  </Link>
                </>
              )}
            </div>
          </div>
        </div>
      </header>

      {/* Hero Section */}
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pt-20 pb-16">
        <div className="text-center">
          <h1 className="text-4xl font-bold text-github-fg dark:text-github-dark-fg sm:text-5xl md:text-6xl">
            Unify Feature Requests
          </h1>
          <p className="mt-3 max-w-md mx-auto text-xl text-github-secondary dark:text-github-dark-secondary sm:text-2xl md:mt-5 md:max-w-3xl">
            Shape the future of Unify&apos;s ordering software by requesting and
            voting on new features.
          </p>
          {!isAuthenticated && (
            <div className="mt-10 flex justify-center gap-4">
              <Link
                href="/api/auth/signin"
                className="px-8 py-3 border border-transparent text-base font-medium rounded-md text-white bg-github-primary dark:bg-github-dark-primary hover:bg-opacity-90"
              >
                Sign in to share your ideas!
              </Link>
            </div>
          )}
        </div>
      </div>

      {/* Features Section */}
      <div className="py-16 bg-github-hover dark:bg-github-dark-hover">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="grid grid-cols-1 gap-8 md:grid-cols-3">
            {/* Request Features */}
            <div className="text-center">
              <div className="flex justify-center">
                <FiCheckCircle className="h-12 w-12 text-github-primary dark:text-github-dark-primary" />
              </div>
              <h3 className="mt-4 text-xl font-semibold text-github-fg dark:text-github-dark-fg">
                Request Features
              </h3>
              <p className="mt-2 text-github-secondary dark:text-github-dark-secondary">
                Submit your ideas for improving the Unify ordering software.
                Whether it&apos;s enhancing order management, inventory control,
                or reporting capabilities.
              </p>
            </div>

            {/* Vote and Prioritize */}
            <div className="text-center">
              <div className="flex justify-center">
                <FiTrendingUp className="h-12 w-12 text-github-primary dark:text-github-dark-primary" />
              </div>
              <h3 className="mt-4 text-xl font-semibold text-github-fg dark:text-github-dark-fg">
                Vote and Prioritize
              </h3>
              <p className="mt-2 text-github-secondary dark:text-github-dark-secondary">
                Vote on feature requests to help prioritize development. Your
                input directly influences which improvements are implemented
                first.
              </p>
            </div>

            {/* Track Progress */}
            <div className="text-center">
              <div className="flex justify-center">
                <FiUsers className="h-12 w-12 text-github-primary dark:text-github-dark-primary" />
              </div>
              <h3 className="mt-4 text-xl font-semibold text-github-fg dark:text-github-dark-fg">
                Track Progress
              </h3>
              <p className="mt-2 text-github-secondary dark:text-github-dark-secondary">
                Stay updated on the status of requested features. Monitor as
                they move from proposal to implementation in Unify.
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* How It Works Section */}
      <div className="py-16">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <h2 className="text-3xl font-bold text-center text-github-fg dark:text-github-dark-fg mb-12">
            How It Works
          </h2>
          <div className="grid grid-cols-1 gap-8 md:grid-cols-2 lg:grid-cols-4">
            <div className="relative">
              <div className="text-xl font-bold text-github-primary dark:text-github-dark-primary mb-2">
                1. Sign In
              </div>
              <p className="text-github-secondary dark:text-github-dark-secondary">
                Sign in to access the feature request platform.
              </p>
            </div>
            <div>
              <div className="text-xl font-bold text-github-primary dark:text-github-dark-primary mb-2">
                2. Submit Requests
              </div>
              <p className="text-github-secondary dark:text-github-dark-secondary">
                Create detailed feature requests for improvements you&apos;d
                like to see in Unify.
              </p>
            </div>
            <div>
              <div className="text-xl font-bold text-github-primary dark:text-github-dark-primary mb-2">
                3. Vote & Discuss
              </div>
              <p className="text-github-secondary dark:text-github-dark-secondary">
                Vote on existing requests and engage in discussions about
                proposed features.
              </p>
            </div>
            <div>
              <div className="text-xl font-bold text-github-primary dark:text-github-dark-primary mb-2">
                4. Stay Updated
              </div>
              <p className="text-github-secondary dark:text-github-dark-secondary">
                Track the progress of approved features as they&apos;re
                implemented into Unify.
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* Footer */}
      <footer className="bg-github-bg dark:bg-github-dark-bg border-t border-github-border dark:border-github-dark-border py-8">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex flex-col md:flex-row justify-between items-center">
            <div className="mb-4 md:mb-0">
              <p className="text-github-secondary dark:text-github-dark-secondary">
                © {new Date().getFullYear()} niallmurray.me. All rights
                reserved.
              </p>
            </div>
            <div className="flex space-x-6">
              <a
                href="#"
                className="text-github-secondary dark:text-github-dark-secondary hover:text-github-primary dark:hover:text-github-dark-primary"
              >
                Terms
              </a>
              <a
                href="#"
                className="text-github-secondary dark:text-github-dark-secondary hover:text-github-primary dark:hover:text-github-dark-primary"
              >
                Privacy
              </a>
              <a
                href="#"
                className="text-github-secondary dark:text-github-dark-secondary hover:text-github-primary dark:hover:text-github-dark-primary"
              >
                Contact
              </a>
            </div>
          </div>
        </div>
      </footer>
    </div>
  );
}
