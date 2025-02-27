import React from "react";
import Link from "next/link";
import Image from "next/image";

type AuthLayoutProps = {
  children: React.ReactNode;
  title: string;
  subtitle?: string;
  showLogo?: boolean;
};

export default function AuthLayout({
  children,
  title,
  subtitle,
  showLogo = true,
}: AuthLayoutProps) {
  return (
    <div className="min-h-screen flex flex-col md:flex-row bg-github-bg dark:bg-github-dark-bg text-github-fg dark:text-github-dark-fg">
      {/* Left side - Brand/Logo section */}
      <div className="hidden md:flex md:w-1/2 bg-github-primary dark:bg-github-dark-accent text-white p-10 flex-col justify-between">
        <div>
          {showLogo && (
            <div className="mb-8">
              <h1 className="text-3xl font-bold">Unify Poll</h1>
              <p className="text-blue-100 mt-2">Your trusted polling platform</p>
            </div>
          )}
          
          <div className="mt-12">
            <h2 className="text-4xl font-bold mb-6">Simple, Secure, Seamless</h2>
            <p className="text-xl text-blue-100">
              Experience the most reliable polling system with advanced security features.
            </p>
          </div>
        </div>
        
        <div className="mt-auto">
          <p className="text-blue-100">
            © {new Date().getFullYear()} niallmurray.me. All rights reserved.
          </p>
        </div>
      </div>
      
      {/* Right side - Form section */}
      <div className="w-full md:w-1/2 p-6 flex items-center justify-center">
        <div className="w-full max-w-md">
          {/* Mobile logo */}
          <div className="md:hidden text-center mb-8">
            {showLogo && (
              <h1 className="text-2xl font-bold text-github-primary dark:text-github-dark-primary">Unify Poll</h1>
            )}
          </div>
          
          <div className="bg-github-bg dark:bg-github-dark-hover rounded-xl shadow-lg p-8 border border-github-border dark:border-github-dark-border">
            <h1 className="text-2xl font-bold mb-2">{title}</h1>
            {subtitle && <p className="text-github-secondary dark:text-github-dark-secondary mb-6">{subtitle}</p>}
            
            {children}
          </div>
        </div>
      </div>
    </div>
  );
} 