"use client";

import Link from "next/link";
import { useSession } from "next-auth/react";
import { useTheme } from "@/context/theme-context";
import { FiMoon, FiSun } from "react-icons/fi";

export default function Home() {
  const { data: session, status } = useSession();
  const isAuthenticated = status === "authenticated";
  const { theme, toggleTheme } = useTheme();

  return (
    <div className="min-h-screen bg-github-bg dark:bg-github-dark-bg text-github-fg dark:text-github-dark-fg">
      {/* Header */}
      <header className="bg-github-bg dark:bg-github-dark-bg border-b border-github-border dark:border-github-dark-border">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-6">
            <div className="flex items-center">
              <h1 className="text-2xl font-bold text-github-primary dark:text-github-dark-primary">SecureAuth</h1>
            </div>
            <div className="flex items-center space-x-4">
              <button
                onClick={toggleTheme}
                className="p-2 rounded-md hover:bg-github-hover dark:hover:bg-github-dark-hover"
                aria-label="Toggle theme"
              >
                {theme === 'dark' ? (
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
                    href="/login"
                    className="px-4 py-2 border border-github-border dark:border-github-dark-border rounded-md text-sm font-medium hover:bg-github-hover dark:hover:bg-github-dark-hover transition-colors"
                  >
                    Sign in
                  </Link>
                  <Link
                    href="/register"
                    className="px-4 py-2 bg-github-primary dark:bg-github-dark-accent border border-transparent rounded-md text-sm font-medium text-white hover:bg-opacity-90 transition-colors"
                  >
                    Sign up
                  </Link>
                </>
              )}
            </div>
          </div>
        </div>
      </header>

      {/* Hero section */}
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-16 md:py-24">
        <div className="text-center">
          <h1 className="text-4xl md:text-5xl lg:text-6xl font-bold mb-6">
            Secure Authentication for Modern Applications
          </h1>
          <p className="text-xl md:text-2xl text-github-secondary dark:text-github-dark-secondary max-w-3xl mx-auto mb-10">
            A complete authentication solution with email verification, password reset, and role-based access control.
          </p>
          <div className="flex flex-col sm:flex-row justify-center gap-4">
            <Link
              href="/register"
              className="px-6 py-3 bg-github-primary dark:bg-github-dark-accent text-white rounded-md text-lg font-medium hover:bg-opacity-90 transition-colors"
            >
              Get Started
            </Link>
            <Link
              href="/login"
              className="px-6 py-3 bg-github-hover dark:bg-github-dark-hover rounded-md text-lg font-medium hover:bg-github-border dark:hover:bg-github-dark-border transition-colors"
            >
              Sign In
            </Link>
          </div>
        </div>
      </div>

      {/* Features section */}
      <div className="bg-github-hover dark:bg-github-dark-hover py-16">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <h2 className="text-3xl font-bold text-center mb-12">Key Features</h2>
          <div className="grid md:grid-cols-3 gap-8">
            <div className="bg-github-bg dark:bg-github-dark-bg p-6 rounded-lg shadow-sm border border-github-border dark:border-github-dark-border">
              <h3 className="text-xl font-semibold mb-3">Secure Authentication</h3>
              <p className="text-github-secondary dark:text-github-dark-secondary">
                Industry-standard security practices with password hashing and protection against common vulnerabilities.
              </p>
            </div>
            <div className="bg-github-bg dark:bg-github-dark-bg p-6 rounded-lg shadow-sm border border-github-border dark:border-github-dark-border">
              <h3 className="text-xl font-semibold mb-3">Email Verification</h3>
              <p className="text-github-secondary dark:text-github-dark-secondary">
                Verify user emails to ensure account security and reduce spam registrations.
              </p>
            </div>
            <div className="bg-github-bg dark:bg-github-dark-bg p-6 rounded-lg shadow-sm border border-github-border dark:border-github-dark-border">
              <h3 className="text-xl font-semibold mb-3">Password Recovery</h3>
              <p className="text-github-secondary dark:text-github-dark-secondary">
                Simple and secure password reset flow for users who forget their credentials.
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
                © {new Date().getFullYear()} SecureAuth. All rights reserved.
              </p>
            </div>
            <div className="flex space-x-6">
              <a href="#" className="text-github-secondary dark:text-github-dark-secondary hover:text-github-primary dark:hover:text-github-dark-primary">
                Terms
              </a>
              <a href="#" className="text-github-secondary dark:text-github-dark-secondary hover:text-github-primary dark:hover:text-github-dark-primary">
                Privacy
              </a>
              <a href="#" className="text-github-secondary dark:text-github-dark-secondary hover:text-github-primary dark:hover:text-github-dark-primary">
                Contact
              </a>
            </div>
          </div>
        </div>
      </footer>
    </div>
  );
}
