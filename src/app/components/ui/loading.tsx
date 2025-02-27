import React from "react";

type LoadingProps = {
  fullScreen?: boolean;
  message?: string;
};

export default function Loading({ 
  fullScreen = true, 
  message = "Loading..." 
}: LoadingProps) {
  const loadingContent = (
    <div className="text-center">
      <div className="w-16 h-16 border-4 border-github-primary dark:border-github-dark-primary border-t-transparent rounded-full animate-spin mx-auto"></div>
      <p className="mt-4 text-github-secondary dark:text-github-dark-secondary">{message}</p>
    </div>
  );

  if (fullScreen) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-github-bg dark:bg-github-dark-bg">
        {loadingContent}
      </div>
    );
  }

  return (
    <div className="py-12 flex items-center justify-center">
      {loadingContent}
    </div>
  );
} 