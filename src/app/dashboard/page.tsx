"use client";

import { useState, useEffect } from "react";
import DashboardLayout from "@/app/components/dashboard-layout";
import {
  FiUser,
  FiMail,
  FiCalendar,
  FiShield,
  FiActivity,
  FiClock,
} from "react-icons/fi";

// Define the Activity type
interface Activity {
  id: string;
  createdAt: string;
  type: string;
  featureRequest: {
    title: string;
  };
  deletedRequestTitle?: string; // Optional if it may not exist
}

export default function Dashboard() {
  const [userData, setUserData] = useState<{
    name?: string;
    email?: string;
    createdAt?: string;
    emailVerified?: Date | null;
    role?: string;
    voteCount?: number;
    featureRequestCount?: number;
  } | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [activities, setActivities] = useState<Activity[]>([]);

  useEffect(() => {
    const fetchUserData = async () => {
      try {
        const response = await fetch("/api/user/profile");
        const data = await response.json();

        if (response.ok) {
          // Fetch the number of votes for the user
          const votesResponse = await fetch(`/api/user/${data.user.id}/votes`);
          const votesData = await votesResponse.json();

          // Fetch the number of feature requests for the user
          const featureRequestCountResponse = await fetch(
            `/api/user/${data.user.id}/feature-requests/count`
          );
          const featureRequestCountData =
            await featureRequestCountResponse.json();

          if (votesResponse.ok && featureRequestCountResponse.ok) {
            setUserData({
              ...data.user,
              voteCount: votesData.count,
              featureRequestCount: featureRequestCountData.count,
            });
          } else {
            if (!votesResponse.ok) {
              console.error("Failed to load user votes");
            }
            if (!featureRequestCountResponse.ok) {
              console.error("Failed to load feature request count");
            }
          }

          // Fetch user activity
          const activityResponse = await fetch(
            `/api/user/${data.user.id}/activity`
          );
          const activityData = await activityResponse.json();

          if (activityResponse.ok) {
            setActivities(activityData);
          } else {
            console.error(
              activityData.message || "Failed to load user activity"
            );
          }
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
        <div className="md:col-span-2 bg-github-bg dark:bg-github-dark-hover rounded-lg shadow-sm border border-github-border dark:border-github-dark-border p-6 h-full">
          <h2 className="text-xl font-semibold mb-4">
            Welcome, {displayName}!
          </h2>
          <p className="text-github-secondary dark:text-github-dark-secondary mb-2">
            This application allows you to manage feature requests effectively.
            You can create new requests, vote on existing ones, and track their
            status.
          </p>
          <p className="text-github-secondary dark:text-github-dark-secondary mb-2">
            Click the "Feature Requests" button on the left to view, vote, or
            create new feature requests.
          </p>
          <p className="text-github-secondary dark:text-github-dark-secondary">
            Use the navigation to explore requests, filter by status, and see
            your voting history. Your feedback helps improve the application!
          </p>
        </div>

        {/* User Info Card */}
        <div className="bg-github-bg dark:bg-github-dark-hover rounded-lg shadow-sm border border-github-border dark:border-github-dark-border p-6">
          <h3 className="text-lg font-medium mb-4">Account Summary</h3>
          {loading ? (
            <div className="animate-pulse space-y-4">
              <div className="h-4 bg-github-border dark:bg-github-dark-border rounded w-3/4"></div>
              <div className="h-4 bg-github-border dark:bg-github-dark-border rounded w-1/2"></div>
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
                <FiActivity className="mt-1 mr-2 text-github-secondary dark:text-github-dark-secondary" />
                <div>
                  <p className="text-sm text-github-secondary dark:text-github-dark-secondary">
                    Votes
                  </p>
                  <p className="font-medium">{userData?.voteCount || 0}</p>
                </div>
              </div>
              <div className="flex items-start">
                <FiActivity className="mt-1 mr-2 text-github-secondary dark:text-github-dark-secondary" />
                <div>
                  <p className="text-sm text-github-secondary dark:text-github-dark-secondary">
                    Feature Requests
                  </p>
                  <p className="font-medium">
                    {userData?.featureRequestCount || 0}
                  </p>
                </div>
              </div>
            </div>
          )}
        </div>

        {/* Activity Card */}
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
              {activities.length === 0 ? (
                <p className="text-gray-500 dark:text-gray-400">
                  No recent activity found.
                </p>
              ) : (
                activities.map((activity) => (
                  <div
                    key={activity.id}
                    className="border-l-2 border-github-primary dark:border-github-dark-primary pl-4 py-2"
                  >
                    <div className="flex items-center text-sm text-github-secondary dark:text-github-dark-secondary mb-1">
                      <FiClock className="mr-2" />
                      <span>
                        {new Date(activity.createdAt).toLocaleDateString()}
                      </span>
                    </div>
                    <p className="text-github-fg dark:text-github-dark-fg">
                      {activity.type === "created"
                        ? `Created feature request: ${activity.featureRequest.title}`
                        : activity.type === "voted"
                        ? `Voted for feature request: ${activity.featureRequest.title}`
                        : activity.type === "unvoted"
                        ? `Removed vote from feature request: ${activity.featureRequest.title}`
                        : activity.type === "edited"
                        ? `Edited feature request: ${activity.featureRequest.title}`
                        : activity.type === "deleted"
                        ? `Deleted feature request: ${activity.deletedRequestTitle}`
                        : `Status changed for feature request: ${activity.featureRequest.title}`}
                    </p>
                  </div>
                ))
              )}
            </div>
          )}
        </div>
      </div>
    </DashboardLayout>
  );
}
