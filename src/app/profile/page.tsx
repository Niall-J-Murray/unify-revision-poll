"use client";

import { useState, useEffect } from "react";
import { useSession } from "next-auth/react";
import { useRouter } from "next/navigation";
import DashboardLayout from "@/app/components/dashboard-layout";
import Input from "@/app/components/ui/input";
import {
  FiCheck,
  FiX,
  FiMail,
  FiLock,
  FiAlertTriangle,
  FiArrowLeft,
  FiUser,
} from "react-icons/fi";
import Link from "next/link";

export default function Profile() {
  const { data: session, update, status } = useSession();
  const router = useRouter();
  const [user, setUser] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [formData, setFormData] = useState({
    name: "",
    email: "",
  });
  const [passwordData, setPasswordData] = useState({
    currentPassword: "",
    newPassword: "",
    confirmPassword: "",
  });
  const [deleteData, setDeleteData] = useState({
    password: "",
  });
  const [updating, setUpdating] = useState(false);
  const [success, setSuccess] = useState("");
  const [error, setError] = useState("");
  const [emailVerified, setEmailVerified] = useState<boolean | null>(null);
  const [showPasswordForm, setShowPasswordForm] = useState(false);
  const [showDeleteForm, setShowDeleteForm] = useState(false);
  const [activeSection, setActiveSection] = useState("profile");

  useEffect(() => {
    if (status === "unauthenticated") {
      router.push("/login");
    }

    const fetchUserData = async () => {
      if (status !== "authenticated") return;

      try {
        const response = await fetch("/api/user/profile");
        const data = await response.json();

        if (response.ok) {
          setUser(data.user);
          setFormData({
            name: data.user.name || "",
            email: data.user.email || "",
          });

          // Check if emailVerified is a date string or boolean
          if (
            typeof data.user.emailVerified === "string" ||
            data.user.emailVerified instanceof Date
          ) {
            setEmailVerified(true);
          } else {
            setEmailVerified(!!data.user.emailVerified);
          }
        } else {
          setError(data.message || "Failed to load profile");
        }
      } catch (err) {
        setError("An error occurred while fetching your profile");
      } finally {
        setLoading(false);
      }
    };

    fetchUserData();

    // Check for hash in URL to determine active section
    if (window.location.hash === "#password") {
      setActiveSection("password");
      setShowPasswordForm(true);
    } else if (window.location.hash === "#delete") {
      setActiveSection("delete");
      setShowDeleteForm(true);
    }
  }, [status, router]);

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const { name, value } = e.target;
    setFormData((prev) => ({ ...prev, [name]: value }));
  };

  const handlePasswordChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const { name, value } = e.target;
    setPasswordData((prev) => ({ ...prev, [name]: value }));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setSuccess("");
    setUpdating(true);

    try {
      const response = await fetch("/api/user/profile", {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          name: formData.name,
        }),
      });

      const data = await response.json();

      if (response.ok) {
        setSuccess("Profile updated successfully!");
        // Update session data
        await update({
          ...session,
          user: {
            ...session?.user,
            name: formData.name,
          },
        });
      } else {
        setError(data.message || "Failed to update profile");
      }
    } catch (err: unknown) {
      const error = err instanceof Error ? err.message : "An error occurred";
      setError("An error occurred while updating your profile");
    } finally {
      setUpdating(false);
    }
  };

  const handlePasswordSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setSuccess("");
    setUpdating(true);

    // Validate passwords
    if (passwordData.newPassword !== passwordData.confirmPassword) {
      setError("New passwords do not match");
      setUpdating(false);
      return;
    }

    if (passwordData.newPassword.length < 8) {
      setError("New password must be at least 8 characters long");
      setUpdating(false);
      return;
    }

    try {
      const response = await fetch("/api/user/change-password", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          currentPassword: passwordData.currentPassword,
          newPassword: passwordData.newPassword,
        }),
      });

      const data = await response.json();

      if (response.ok) {
        setSuccess("Password changed successfully!");
        setPasswordData({
          currentPassword: "",
          newPassword: "",
          confirmPassword: "",
        });
        setShowPasswordForm(false);
      } else {
        setError(data.message || "Failed to change password");
      }
    } catch (err: unknown) {
      const error = err instanceof Error ? err.message : "An error occurred";
      setError("An error occurred while changing your password");
    } finally {
      setUpdating(false);
    }
  };

  const handleDeleteAccount = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setUpdating(true);

    try {
      const response = await fetch("/api/user/delete-account", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          password: deleteData.password,
        }),
      });

      const data = await response.json();

      if (response.ok) {
        // Redirect to login with deleted parameter
        router.push("/login?deleted=true");
      } else {
        setError(data.message || "Failed to delete account");
      }
    } catch (err: unknown) {
      const error = err instanceof Error ? err.message : "An error occurred";
      setError("An error occurred while deleting your account");
    } finally {
      setUpdating(false);
    }
  };

  const resendVerificationEmail = async () => {
    try {
      setUpdating(true);
      const response = await fetch("/api/auth/resend-verification", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ email: formData.email }),
      });

      const data = await response.json();

      if (response.ok) {
        setSuccess("Verification email sent successfully!");
        setError("");
      } else {
        setError(data.message || "Failed to resend verification email");
      }
    } catch (err: unknown) {
      const error = err instanceof Error ? err.message : "An error occurred";
      setError("An error occurred while sending verification email");
    } finally {
      setUpdating(false);
    }
  };

  if (loading) {
    return (
      <DashboardLayout title="Profile">
        <div className="flex justify-center items-center h-64">
          <div className="animate-spin rounded-full h-12 w-12 border-t-2 border-b-2 border-github-primary dark:border-github-dark-primary"></div>
        </div>
      </DashboardLayout>
    );
  }

  return (
    <DashboardLayout title="Profile">
      <div className="max-w-3xl mx-auto">
        <div className="mb-6">
          <Link
            href="/dashboard"
            className="inline-flex items-center text-github-primary dark:text-github-dark-primary hover:underline"
          >
            <FiArrowLeft className="mr-2" />
            Back to Dashboard
          </Link>
        </div>

        {error && (
          <div className="mb-6 p-3 bg-red-50 text-red-700 rounded-lg border border-red-200 text-sm">
            {error}
          </div>
        )}

        {success && (
          <div className="mb-6 p-3 bg-green-50 text-green-700 rounded-lg border border-green-200 text-sm">
            {success}
          </div>
        )}

        <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
          {/* Sidebar */}
          <div className="md:col-span-1">
            <div className="bg-github-bg dark:bg-github-dark-hover rounded-lg shadow-sm border border-github-border dark:border-github-dark-border p-4">
              <nav className="space-y-1">
                <button
                  onClick={() => setActiveSection("profile")}
                  className={`w-full text-left px-3 py-2 rounded-md flex items-center ${
                    activeSection === "profile"
                      ? "bg-github-primary dark:bg-github-dark-accent text-white"
                      : "hover:bg-github-hover dark:hover:bg-github-dark-hover"
                  }`}
                >
                  <FiUser className="mr-2" />
                  Profile Information
                </button>
                <button
                  onClick={() => {
                    setActiveSection("password");
                    setShowPasswordForm(true);
                  }}
                  className={`w-full text-left px-3 py-2 rounded-md flex items-center ${
                    activeSection === "password"
                      ? "bg-github-primary dark:bg-github-dark-accent text-white"
                      : "hover:bg-github-hover dark:hover:bg-github-dark-hover"
                  }`}
                >
                  <FiLock className="mr-2" />
                  Change Password
                </button>
                <button
                  onClick={() => {
                    setActiveSection("delete");
                    setShowDeleteForm(true);
                  }}
                  className={`w-full text-left px-3 py-2 rounded-md flex items-center text-red-600 dark:text-red-400 ${
                    activeSection === "delete"
                      ? "bg-red-100 dark:bg-red-900/20"
                      : "hover:bg-red-50 dark:hover:bg-red-900/10"
                  }`}
                >
                  <FiAlertTriangle className="mr-2" />
                  Delete Account
                </button>
              </nav>
            </div>
          </div>

          {/* Main content */}
          <div className="md:col-span-3">
            <div className="bg-github-bg dark:bg-github-dark-hover rounded-lg shadow-sm border border-github-border dark:border-github-dark-border p-6">
              {/* Profile Information */}
              {activeSection === "profile" && (
                <>
                  <h2 className="text-xl font-semibold mb-6">
                    Profile Information
                  </h2>

                  <form onSubmit={handleSubmit} className="space-y-4">
                    <Input
                      id="name"
                      name="name"
                      type="text"
                      label="Full Name"
                      value={formData.name}
                      onChange={handleChange}
                    />

                    <div className="space-y-2">
                      <label className="block text-sm font-medium">
                        Email Address
                      </label>
                      <div className="flex items-center">
                        <span className="block w-full px-3 py-2 border border-github-border dark:border-github-dark-border bg-github-hover dark:bg-github-dark-hover rounded-md text-github-secondary dark:text-github-dark-secondary">
                          {formData.email}
                        </span>
                      </div>
                      <p className="text-xs text-github-secondary dark:text-github-dark-secondary flex items-center mt-1">
                        {emailVerified ? (
                          <>
                            <FiCheck className="text-green-500 mr-1" />
                            <span className="text-green-600 dark:text-green-400">
                              Email verified
                            </span>
                          </>
                        ) : (
                          <>
                            <FiX className="text-yellow-500 mr-1" />
                            <span className="text-yellow-600 dark:text-yellow-400">
                              Email not verified.{" "}
                              <button
                                type="button"
                                onClick={resendVerificationEmail}
                                className="text-github-primary dark:text-github-dark-primary hover:underline"
                                disabled={updating}
                              >
                                Resend verification email
                              </button>
                            </span>
                          </>
                        )}
                      </p>
                    </div>

                    <div className="pt-4">
                      <button
                        type="submit"
                        disabled={updating}
                        className="px-4 py-2 bg-github-primary dark:bg-github-dark-accent text-white rounded-md hover:bg-opacity-90 focus:outline-none focus:ring-2 focus:ring-github-primary dark:focus:ring-github-dark-primary focus:ring-offset-2 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                      >
                        {updating ? "Saving..." : "Save Changes"}
                      </button>
                    </div>
                  </form>
                </>
              )}

              {/* Change Password */}
              {activeSection === "password" && (
                <>
                  <h2 className="text-xl font-semibold mb-6">
                    Change Password
                  </h2>

                  <form onSubmit={handlePasswordSubmit} className="space-y-4">
                    <Input
                      id="currentPassword"
                      name="currentPassword"
                      type="password"
                      label="Current Password"
                      value={passwordData.currentPassword}
                      onChange={handlePasswordChange}
                      required
                    />

                    <Input
                      id="newPassword"
                      name="newPassword"
                      type="password"
                      label="New Password"
                      value={passwordData.newPassword}
                      onChange={handlePasswordChange}
                      required
                    />

                    <Input
                      id="confirmPassword"
                      name="confirmPassword"
                      type="password"
                      label="Confirm New Password"
                      value={passwordData.confirmPassword}
                      onChange={handlePasswordChange}
                      required
                    />

                    <div className="pt-4">
                      <button
                        type="submit"
                        disabled={updating}
                        className="px-4 py-2 bg-github-primary dark:bg-github-dark-accent text-white rounded-md hover:bg-opacity-90 focus:outline-none focus:ring-2 focus:ring-github-primary dark:focus:ring-github-dark-primary focus:ring-offset-2 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                      >
                        {updating ? "Updating..." : "Change Password"}
                      </button>
                    </div>
                  </form>
                </>
              )}

              {/* Delete Account */}
              {activeSection === "delete" && (
                <>
                  <h2 className="text-xl font-semibold mb-6 text-red-600 dark:text-red-400">
                    Delete Account
                  </h2>

                  <div className="p-4 bg-red-50 dark:bg-red-900/20 text-red-700 dark:text-red-400 rounded-lg border border-red-200 dark:border-red-800/30 mb-6">
                    <div className="flex items-start">
                      <FiAlertTriangle className="h-5 w-5 mr-2 mt-0.5" />
                      <div>
                        <h3 className="font-medium">
                          Warning: This action cannot be undone
                        </h3>
                        <p className="mt-1 text-sm">
                          When you delete your account, all your data will be
                          permanently removed. This action cannot be reversed.
                        </p>
                      </div>
                    </div>
                  </div>

                  <form onSubmit={handleDeleteAccount} className="space-y-4">
                    <Input
                      id="deletePassword"
                      name="password"
                      type="password"
                      label="Enter your password to confirm account deletion"
                      value={deleteData.password}
                      onChange={(e) =>
                        setDeleteData({ password: e.target.value })
                      }
                      required
                    />

                    <div className="pt-4">
                      <button
                        type="submit"
                        disabled={updating}
                        className="px-4 py-2 bg-red-600 text-white rounded-md hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                      >
                        {updating
                          ? "Processing..."
                          : "Permanently Delete Account"}
                      </button>
                    </div>
                  </form>
                </>
              )}
            </div>
          </div>
        </div>
      </div>
    </DashboardLayout>
  );
}
