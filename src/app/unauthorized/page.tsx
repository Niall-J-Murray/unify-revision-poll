"use client";

import Link from "next/link";

export default function Unauthorized() {
  return (
    <div className="min-h-screen flex items-center justify-center p-6 bg-gray-50">
      <div className="max-w-md w-full bg-white p-8 rounded-lg shadow-md text-center">
        <div className="text-red-600 mb-6">
          <svg xmlns="http://www.w3.org/2000/svg" className="h-16 w-16 mx-auto" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
          </svg>
        </div>
        
        <h1 className="text-2xl font-bold mb-4 text-gray-800">Access Denied</h1>
        
        <p className="text-gray-700 mb-6">
          You don't have permission to access this page. Please contact an administrator if you believe this is an error.
        </p>
        
        <div className="flex flex-col space-y-2">
          <Link
            href="/dashboard"
            className="bg-blue-600 text-white py-2 px-4 rounded-md hover:bg-blue-700 transition-colors"
          >
            Go to Dashboard
          </Link>
          
          <Link
            href="/"
            className="bg-gray-600 text-white py-2 px-4 rounded-md hover:bg-gray-700 transition-colors"
          >
            Back to Home
          </Link>
        </div>
      </div>
    </div>
  );
} 