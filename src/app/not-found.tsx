import Link from "next/link";

export default function NotFound() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-github-bg dark:bg-github-dark-bg text-github-fg dark:text-github-dark-fg px-4">
      <div className="max-w-md w-full text-center">
        <h1 className="text-6xl font-bold text-github-primary dark:text-github-dark-primary mb-4">404</h1>
        <h2 className="text-2xl font-bold mb-4">
          Page Not Found
        </h2>
        <p className="text-github-secondary dark:text-github-dark-secondary mb-8">
          The page you are looking for doesn't exist or has been moved.
        </p>
        <Link
          href="/"
          className="px-4 py-2 bg-github-primary dark:bg-github-dark-accent text-white rounded-md hover:bg-opacity-90 transition-colors"
        >
          Go to homepage
        </Link>
      </div>
    </div>
  );
} 