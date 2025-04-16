"use client";

import { useEffect } from "react";
import Link from "next/link";

export default function ErrorComponent({
  error,
  reset,
}: Readonly<{
  error: Error & { digest?: string };
  reset: () => void;
}>) {
  useEffect(() => {
    // Log the error to an error reporting service
    console.error(error);
  }, [error]);

  return (
    <div className="min-h-screen flex items-center justify-center bg-github-bg dark:bg-github-dark-bg text-github-fg dark:text-github-dark-fg px-4">
      <div className="max-w-md w-full text-center">
        <div className="text-red-500 mb-4">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            className="h-16 w-16 mx-auto"
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
        <h1 className="text-2xl font-bold mb-4">Something went wrong</h1>
        <p className="text-github-secondary dark:text-github-dark-secondary mb-8">
          We apologize for the inconvenience. Please try again or contact
          support if the problem persists.
        </p>
        <div className="flex flex-col sm:flex-row space-y-3 sm:space-y-0 sm:space-x-3 justify-center">
          <button
            onClick={reset}
            className="px-4 py-2 bg-github-primary dark:bg-github-dark-accent text-white rounded-md hover:bg-opacity-90 transition-colors"
          >
            Try again
          </button>
          <Link
            href="/"
            className="px-4 py-2 bg-github-hover dark:bg-github-dark-hover text-github-fg dark:text-github-dark-fg rounded-md hover:bg-github-border dark:hover:bg-github-dark-border transition-colors"
          >
            Go to homepage
          </Link>
        </div>
      </div>
    </div>
  );
}
