"use client";

import { useState, useEffect } from "react";
import { useSession } from "next-auth/react";
import { useRouter } from "next/navigation";
import DashboardLayout from "@/app/components/dashboard-layout";
import { FiUsers, FiUserX, FiUserCheck, FiRefreshCw } from "react-icons/fi";

type User = {
  id: string;
  name: string | null;
  email: string;
  emailVerified: Date | null;
  role: string;
  createdAt: Date;
};

export default function AdminDashboard() {
  const { data: session, status } = useSession();
  const router = useRouter();
  const [users, setUsers] = useState<User[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    if (status === "unauthenticated") {
      router.push("/login");
      return;
    }

    if (status === "authenticated") {
      if (session.user.role !== "ADMIN") {
        router.push("/dashboard");
        return;
      }

      fetchUsers();
    }
  }, [status, session, router]);

  const fetchUsers = async () => {
    try {
      const response = await fetch("/api/admin/users");
      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.message || "Failed to fetch users");
      }

      setUsers(data.users);
    } catch (err: any) {
      setError(err.message || "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  if (status === "loading" || loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-github-bg dark:bg-github-dark-bg">
        <div className="text-center">
          <div className="w-16 h-16 border-4 border-github-primary dark:border-github-dark-primary border-t-transparent rounded-full animate-spin mx-auto"></div>
          <p className="mt-4 text-github-fg dark:text-github-dark-fg">
            Loading...
          </p>
        </div>
      </div>
    );
  }

  if (!session?.user || session.user.role !== "ADMIN") {
    return null; // Will redirect in useEffect
  }

  return (
    <DashboardLayout title="Admin Dashboard">
      <div className="space-y-6">
        {/* Stats */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <div className="bg-github-bg dark:bg-github-dark-hover rounded-lg shadow-sm border border-github-border dark:border-github-dark-border p-6">
            <div className="flex items-center">
              <div className="p-3 rounded-full bg-blue-100 dark:bg-blue-900/20 text-blue-600 dark:text-blue-400">
                <FiUsers className="h-6 w-6" />
              </div>
              <div className="ml-4">
                <h3 className="text-lg font-medium text-github-fg dark:text-github-dark-fg">
                  Total Users
                </h3>
                <p className="text-2xl font-bold text-github-fg dark:text-github-dark-fg">
                  {users.length}
                </p>
              </div>
            </div>
          </div>

          <div className="bg-github-bg dark:bg-github-dark-hover rounded-lg shadow-sm border border-github-border dark:border-github-dark-border p-6">
            <div className="flex items-center">
              <div className="p-3 rounded-full bg-green-100 dark:bg-green-900/20 text-green-600 dark:text-green-400">
                <FiUserCheck className="h-6 w-6" />
              </div>
              <div className="ml-4">
                <h3 className="text-lg font-medium text-github-fg dark:text-github-dark-fg">
                  Verified Users
                </h3>
                <p className="text-2xl font-bold text-github-fg dark:text-github-dark-fg">
                  {users.filter((user) => user.emailVerified).length}
                </p>
              </div>
            </div>
          </div>

          <div className="bg-github-bg dark:bg-github-dark-hover rounded-lg shadow-sm border border-github-border dark:border-github-dark-border p-6">
            <div className="flex items-center">
              <div className="p-3 rounded-full bg-yellow-100 dark:bg-yellow-900/20 text-yellow-600 dark:text-yellow-400">
                <FiUserX className="h-6 w-6" />
              </div>
              <div className="ml-4">
                <h3 className="text-lg font-medium text-github-fg dark:text-github-dark-fg">
                  Unverified Users
                </h3>
                <p className="text-2xl font-bold text-github-fg dark:text-github-dark-fg">
                  {users.filter((user) => !user.emailVerified).length}
                </p>
              </div>
            </div>
          </div>
        </div>

        {/* User List */}
        <div className="bg-github-bg dark:bg-github-dark-hover rounded-lg shadow-sm border border-github-border dark:border-github-dark-border overflow-hidden">
          <div className="p-6 border-b border-github-border dark:border-github-dark-border flex justify-between items-center">
            <h2 className="text-xl font-semibold text-github-fg dark:text-github-dark-fg">
              User Management
            </h2>
            <button
              onClick={fetchUsers}
              className="flex items-center text-github-primary dark:text-github-dark-primary hover:text-opacity-80"
            >
              <FiRefreshCw className="mr-1" /> Refresh
            </button>
          </div>

          {error && (
            <div className="p-4 bg-red-50 dark:bg-red-900/20 text-red-700 dark:text-red-400 border-b border-red-200 dark:border-red-800/30">
              {error}
            </div>
          )}

          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-github-border dark:divide-github-dark-border">
              <thead className="bg-github-hover dark:bg-github-dark-hover">
                <tr>
                  <th
                    scope="col"
                    className="px-6 py-3 text-left text-xs font-medium text-github-secondary dark:text-github-dark-secondary uppercase tracking-wider"
                  >
                    User
                  </th>
                  <th
                    scope="col"
                    className="px-6 py-3 text-left text-xs font-medium text-github-secondary dark:text-github-dark-secondary uppercase tracking-wider"
                  >
                    Status
                  </th>
                  <th
                    scope="col"
                    className="px-6 py-3 text-left text-xs font-medium text-github-secondary dark:text-github-dark-secondary uppercase tracking-wider"
                  >
                    Role
                  </th>
                  <th
                    scope="col"
                    className="px-6 py-3 text-left text-xs font-medium text-github-secondary dark:text-github-dark-secondary uppercase tracking-wider"
                  >
                    Joined
                  </th>
                  <th
                    scope="col"
                    className="px-6 py-3 text-right text-xs font-medium text-github-secondary dark:text-github-dark-secondary uppercase tracking-wider"
                  >
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody className="bg-github-bg dark:bg-github-dark-bg divide-y divide-github-border dark:divide-github-dark-border">
                {users.length > 0 ? (
                  users.map((user) => (
                    <tr
                      key={user.id}
                      className="hover:bg-github-hover dark:hover:bg-github-dark-hover"
                    >
                      <td className="px-6 py-4 whitespace-nowrap">
                        <div className="flex items-center">
                          <div className="h-10 w-10 rounded-full bg-github-primary/20 dark:bg-github-dark-primary/20 flex items-center justify-center text-github-primary dark:text-github-dark-primary font-semibold">
                            {(user.name
                              ? user.name.charAt(0)
                              : user.email.charAt(0)
                            ).toUpperCase()}
                          </div>
                          <div className="ml-4">
                            <div className="text-sm font-medium text-github-fg dark:text-github-dark-fg">
                              {user.name || "No name"}
                            </div>
                            <div className="text-sm text-github-secondary dark:text-github-dark-secondary">
                              {user.email}
                            </div>
                          </div>
                        </div>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        {user.emailVerified ? (
                          <span className="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-400">
                            Verified
                          </span>
                        ) : (
                          <span className="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-yellow-100 dark:bg-yellow-900/30 text-yellow-800 dark:text-yellow-400">
                            Unverified
                          </span>
                        )}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-github-secondary dark:text-github-dark-secondary">
                        {user.role}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-github-secondary dark:text-github-dark-secondary">
                        {new Date(user.createdAt).toLocaleDateString()}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                        <button className="text-github-primary dark:text-github-dark-primary hover:text-opacity-80 mr-3">
                          Edit
                        </button>
                        <button className="text-red-600 dark:text-red-400 hover:text-opacity-80">
                          Delete
                        </button>
                      </td>
                    </tr>
                  ))
                ) : (
                  <tr>
                    <td
                      colSpan={5}
                      className="px-6 py-4 text-center text-github-secondary dark:text-github-dark-secondary"
                    >
                      No users found
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </DashboardLayout>
  );
}
