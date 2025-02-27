import React from "react";
import Link from "next/link";
import { useSession, signOut } from "next-auth/react";
import {
  FiHome,
  FiUser,
  FiSettings,
  FiLogOut,
  FiMenu,
  FiX,
  FiMoon,
  FiSun,
} from "react-icons/fi";
import { useTheme } from "@/context/theme-context";

type DashboardLayoutProps = {
  children: React.ReactNode;
  title: string;
};

export default function DashboardLayout({
  children,
  title,
}: DashboardLayoutProps) {
  const { data: session } = useSession();
  const [sidebarOpen, setSidebarOpen] = React.useState(false);
  const { theme, toggleTheme } = useTheme();
  const [dropdownOpen, setDropdownOpen] = React.useState(false);

  const handleSignOut = async () => {
    await signOut({ redirect: false });
    window.location.href = "/";
  };

  const user = session?.user;
  const displayName = user?.name || user?.email?.split("@")[0] || "User";

  return (
    <div className="min-h-screen bg-github-bg dark:bg-github-dark-bg text-github-fg dark:text-github-dark-fg">
      {/* Mobile sidebar toggle */}
      <div className="lg:hidden fixed top-0 left-0 right-0 z-20 bg-github-bg dark:bg-github-dark-bg border-b border-github-border dark:border-github-dark-border p-4 flex items-center justify-between">
        <button
          onClick={() => setSidebarOpen(!sidebarOpen)}
          className="text-github-secondary dark:text-github-dark-secondary focus:outline-none focus:ring-2 focus:ring-github-primary dark:focus:ring-github-dark-primary p-2 rounded-md"
        >
          {sidebarOpen ? <FiX size={24} /> : <FiMenu size={24} />}
        </button>
        <h1 className="text-xl font-semibold">{title}</h1>

        {/* Mobile user menu */}
        <div className="relative">
          <button
            onClick={() => setDropdownOpen(!dropdownOpen)}
            className="h-8 w-8 rounded-full bg-github-hover dark:bg-github-dark-hover flex items-center justify-center text-github-primary dark:text-github-dark-primary font-semibold"
          >
            {displayName.charAt(0).toUpperCase()}
          </button>

          {dropdownOpen && (
            <div className="absolute right-0 mt-2 w-48 bg-github-bg dark:bg-github-dark-hover border border-github-border dark:border-github-dark-border rounded-md shadow-lg z-30">
              <div className="p-2 border-b border-github-border dark:border-github-dark-border">
                <p className="font-medium">{displayName}</p>
                <p className="text-xs text-github-secondary dark:text-github-dark-secondary truncate">
                  {user?.email}
                </p>
              </div>
              <div className="p-1">
                <button
                  onClick={toggleTheme}
                  className="w-full text-left px-3 py-2 text-sm rounded-md hover:bg-github-hover dark:hover:bg-github-dark-border flex items-center"
                >
                  {theme === "dark" ? (
                    <>
                      <FiSun className="mr-2" />
                      Light Mode
                    </>
                  ) : (
                    <>
                      <FiMoon className="mr-2" />
                      Dark Mode
                    </>
                  )}
                </button>
                <button
                  onClick={handleSignOut}
                  className="w-full text-left px-3 py-2 text-sm text-red-600 dark:text-red-400 rounded-md hover:bg-red-50 dark:hover:bg-red-900/20 flex items-center"
                >
                  <FiLogOut className="mr-2" />
                  Sign out
                </button>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Sidebar */}
      <div
        className={`fixed inset-y-0 left-0 z-10 w-64 bg-github-bg dark:bg-github-dark-bg border-r border-github-border dark:border-github-dark-border transform ${
          sidebarOpen ? "translate-x-0" : "-translate-x-full"
        } lg:translate-x-0 transition-transform duration-300 ease-in-out`}
      >
        <div className="h-full flex flex-col">
          {/* Logo */}
          <div className="p-6 border-b border-github-border dark:border-github-dark-border">
            <h2 className="text-2xl font-bold text-github-primary dark:text-github-dark-primary">
              SecureAuth
            </h2>
          </div>

          {/* Navigation */}
          <nav className="flex-1 p-4 space-y-1">
            <Link
              href="/dashboard"
              className="flex items-center space-x-3 p-3 rounded-md hover:bg-github-hover dark:hover:bg-github-dark-hover"
            >
              <FiHome className="h-5 w-5" />
              <span>Dashboard</span>
            </Link>

            <Link
              href="/profile"
              className="flex items-center space-x-3 p-3 rounded-md hover:bg-github-hover dark:hover:bg-github-dark-hover"
            >
              <FiUser className="h-5 w-5" />
              <span>Profile</span>
            </Link>

            {/* Admin link (conditional) */}
            {session?.user.role === "ADMIN" && (
              <Link
                href="/admin"
                className="flex items-center space-x-3 p-3 rounded-md hover:bg-github-hover dark:hover:bg-github-dark-hover"
              >
                <FiSettings className="h-5 w-5" />
                <span>Admin Panel</span>
              </Link>
            )}
          </nav>
        </div>
      </div>

      {/* Main content */}
      <div className="lg:pl-64">
        <div className="pt-16 lg:pt-0">
          {/* Header */}
          <header className="hidden lg:block bg-github-bg dark:bg-github-dark-bg border-b border-github-border dark:border-github-dark-border">
            <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 flex justify-between items-center">
              <div className="py-6">
                <h1 className="text-2xl font-bold">{title}</h1>
              </div>

              {/* Desktop user menu */}
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

                <div className="relative">
                  <button
                    onClick={() => setDropdownOpen(!dropdownOpen)}
                    className="flex items-center space-x-2 p-2 rounded-md hover:bg-github-hover dark:hover:bg-github-dark-hover"
                  >
                    <div className="h-8 w-8 rounded-full bg-github-hover dark:bg-github-dark-hover flex items-center justify-center text-github-primary dark:text-github-dark-primary font-semibold">
                      {displayName.charAt(0).toUpperCase()}
                    </div>
                    <span className="hidden md:inline-block">
                      {displayName}
                    </span>
                  </button>

                  {dropdownOpen && (
                    <div className="absolute right-0 mt-2 w-48 bg-github-bg dark:bg-github-dark-hover border border-github-border dark:border-github-dark-border rounded-md shadow-lg z-30">
                      <div className="p-2 border-b border-github-border dark:border-github-dark-border">
                        <p className="font-medium">{displayName}</p>
                        <p className="text-xs text-github-secondary dark:text-github-dark-secondary truncate">
                          {user?.email}
                        </p>
                      </div>
                      <div className="p-1">
                        <Link
                          href="/profile"
                          className="px-3 py-2 text-sm rounded-md hover:bg-github-hover dark:hover:bg-github-dark-border flex items-center"
                          onClick={() => setDropdownOpen(false)}
                        >
                          <FiUser className="mr-2" />
                          Your Profile
                        </Link>
                        <button
                          onClick={handleSignOut}
                          className="w-full text-left px-3 py-2 text-sm text-red-600 dark:text-red-400 rounded-md hover:bg-red-50 dark:hover:bg-red-900/20 flex items-center"
                        >
                          <FiLogOut className="mr-2" />
                          Sign out
                        </button>
                      </div>
                    </div>
                  )}
                </div>
              </div>
            </div>
          </header>

          {/* Page content */}
          <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
            {children}
          </main>
        </div>
      </div>

      {/* Mobile sidebar backdrop */}
      {sidebarOpen && (
        <div
          className="fixed inset-0 bg-github-fg/20 dark:bg-black/50 z-0 lg:hidden"
          onClick={() => setSidebarOpen(false)}
        ></div>
      )}

      {/* Mobile dropdown backdrop */}
      {dropdownOpen && (
        <div
          className="fixed inset-0 z-20 lg:hidden"
          onClick={() => setDropdownOpen(false)}
        ></div>
      )}
    </div>
  );
}
