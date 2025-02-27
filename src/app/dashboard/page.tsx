"use client";

import { useState, useEffect } from "react";
import { useSession } from "next-auth/react";
import Link from "next/link";
import DashboardLayout from "@/app/components/dashboard-layout";
import {
  FiUser,
  FiMail,
  FiCalendar,
  FiShield,
  FiCheck,
  FiX,
  FiActivity,
  FiClock,
} from "react-icons/fi";

export default function Dashboard() {
  const { data: session } = useSession();
  const [userData, setUserData] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    const fetchUserData = async () => {
      try {
        const response = await fetch("/api/user/profile");
        const data = await response.json();

        if (response.ok) {
          setUserData(data.user);
        } else {
          setError(data.message || "Failed to load user data");
        }
      } catch (error) {
        console.error("Error fetching user data:", error);
        setError("An error occurred while fetching your profile");
      } finally {
        setLoading(false);
      }
    };

    fetchUserData();
  }, []);

  const formatDate = (dateString: string) => {
    if (!dateString) return "N/A";
    const date = new Date(dateString);
    return date.toLocaleDateString("en-US", {
      year: "numeric",
      month: "long",
      day: "numeric",
    });
  };

  const displayName =
    userData?.name || userData?.email?.split("@")[0] || "User";
  const joinDate = userData?.createdAt
    ? formatDate(userData.createdAt)
    : "Unknown";
  const emailVerified = userData?.emailVerified ? true : false;

  return (
    <DashboardLayout title="Dashboard">
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        {/* Welcome Card */}
        <div className="md:col-span-2 bg-github-bg dark:bg-github-dark-hover rounded-lg shadow-sm border border-github-border dark:border-github-dark-border p-6">
          <h2 className="text-xl font-semibold mb-4">
            Welcome, {displayName}!
          </h2>
          <p className="text-github-secondary dark:text-github-dark-secondary">
            This is your secure authentication dashboard. Here you can see your
            account information and recent activity.
          </p>
        </div>

        {/* User Info Card */}
        <div className="bg-github-bg dark:bg-github-dark-hover rounded-lg shadow-sm border border-github-border dark:border-github-dark-border p-6">
          <h3 className="text-lg font-medium mb-4">Account Information</h3>
          {loading ? (
            <div className="animate-pulse space-y-4">
              <div className="h-4 bg-github-border dark:bg-github-dark-border rounded w-3/4"></div>
              <div className="h-4 bg-github-border dark:bg-github-dark-border rounded w-1/2"></div>
              <div className="h-4 bg-github-border dark:bg-github-dark-border rounded w-5/6"></div>
            </div>
          ) : error ? (
            <div className="text-red-600 dark:text-red-400">{error}</div>
          ) : (
            <div className="space-y-4">
              <div className="flex items-start">
                <FiUser className="mt-1 mr-2 text-github-secondary dark:text-github-dark-secondary" />
                <div>
                  <p className="text-sm text-github-secondary dark:text-github-dark-secondary">
                    Name
                  </p>
                  <p className="font-medium">{userData?.name || "Not set"}</p>
                </div>
              </div>
              <div className="flex items-start">
                <FiMail className="mt-1 mr-2 text-github-secondary dark:text-github-dark-secondary" />
                <div>
                  <p className="text-sm text-github-secondary dark:text-github-dark-secondary">
                    Email
                  </p>
                  <p className="font-medium">{userData?.email}</p>
                  <p className="text-xs mt-1">
                    {emailVerified ? (
                      <span className="text-green-600 dark:text-green-400">
                        Verified
                      </span>
                    ) : (
                      <span className="text-red-600 dark:text-red-400">
                        Not verified
                      </span>
                    )}
                  </p>
                </div>
              </div>
              <div className="flex items-start">
                <FiCalendar className="mt-1 mr-2 text-github-secondary dark:text-github-dark-secondary" />
                <div>
                  <p className="text-sm text-github-secondary dark:text-github-dark-secondary">
                    Joined
                  </p>
                  <p className="font-medium">{joinDate}</p>
                </div>
              </div>
              <div className="flex items-start">
                <FiShield className="mt-1 mr-2 text-github-secondary dark:text-github-dark-secondary" />
                <div>
                  <p className="text-sm text-github-secondary dark:text-github-dark-secondary">
                    Role
                  </p>
                  <p className="font-medium capitalize">
                    {userData?.role?.toLowerCase() || "User"}
                  </p>
                </div>
              </div>
            </div>
          )}
        </div>

        {/* Activity Card - Replacing Profile Card */}
        <div className="md:col-span-3 bg-github-bg dark:bg-github-dark-hover rounded-lg shadow-sm border border-github-border dark:border-github-dark-border p-6">
          <h3 className="text-lg font-medium mb-4 flex items-center">
            <FiActivity className="mr-2" />
            Recent Activity
          </h3>

          {loading ? (
            <div className="animate-pulse space-y-4">
              <div className="h-4 bg-github-border dark:bg-github-dark-border rounded w-3/4"></div>
              <div className="h-4 bg-github-border dark:bg-github-dark-border rounded w-1/2"></div>
              <div className="h-4 bg-github-border dark:bg-github-dark-border rounded w-5/6"></div>
            </div>
          ) : (
            <div className="space-y-4">
              <div className="border-l-2 border-github-primary dark:border-github-dark-primary pl-4 py-2">
                <div className="flex items-center text-sm text-github-secondary dark:text-github-dark-secondary mb-1">
                  <FiClock className="mr-2" />
                  <span>Today</span>
                </div>
                <p className="text-github-fg dark:text-github-dark-fg">
                  Logged in to your account
                </p>
              </div>

              {emailVerified ? (
                <div className="border-l-2 border-green-500 dark:border-green-400 pl-4 py-2">
                  <div className="flex items-center text-sm text-github-secondary dark:text-github-dark-secondary mb-1">
                    <FiClock className="mr-2" />
                    <span>Account Status</span>
                  </div>
                  <p className="text-github-fg dark:text-github-dark-fg">
                    Email verified successfully
                  </p>
                </div>
              ) : (
                <div className="border-l-2 border-yellow-500 dark:border-yellow-400 pl-4 py-2">
                  <div className="flex items-center text-sm text-github-secondary dark:text-github-dark-secondary mb-1">
                    <FiClock className="mr-2" />
                    <span>Action Required</span>
                  </div>
                  <p className="text-github-fg dark:text-github-dark-fg">
                    Please verify your email address
                  </p>
                  <p className="text-sm mt-1">
                    <Link
                      href="/profile"
                      className="text-github-primary dark:text-github-dark-primary hover:underline"
                    >
                      Resend verification email
                    </Link>
                  </p>
                </div>
              )}

              <div className="border-l-2 border-github-border dark:border-github-dark-border pl-4 py-2">
                <div className="flex items-center text-sm text-github-secondary dark:text-github-dark-secondary mb-1">
                  <FiClock className="mr-2" />
                  <span>{joinDate}</span>
                </div>
                <p className="text-github-fg dark:text-github-dark-fg">
                  Account created
                </p>
              </div>
            </div>
          )}
        </div>
      </div>
    </DashboardLayout>
  );
}
