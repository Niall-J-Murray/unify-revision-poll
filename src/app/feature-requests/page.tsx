"use client";

import { useState, useEffect } from "react";
import { useSession } from "next-auth/react";
import DashboardLayout from "@/app/components/dashboard-layout";
import { FiThumbsUp, FiPlus, FiTrash2, FiFilter } from "react-icons/fi";
import Button from "@/app/components/Button";
import FeatureRequestCard from "@/app/components/feature-request-card";
import EditFeatureRequestModal from "@/app/components/edit-feature-request-modal";

type FeatureRequest = {
  id: string;
  title: string;
  description: string;
  createdAt: string;
  status: string;
  user: {
    name: string;
    email: string;
  };
  voteCount: number;
  votes: { userId: string }[];
};

type StatusBadgeProps = {
  status: string;
};

type SortOption = 'votes' | 'newest' | 'oldest';

function StatusBadge({ status }: StatusBadgeProps) {
  const getStatusStyles = () => {
    switch (status) {
      case "OPEN":
        return "bg-yellow-100 text-yellow-800 dark:bg-yellow-900/20 dark:text-yellow-400";
      case "IN_PROGRESS":
        return "bg-blue-100 text-blue-800 dark:bg-blue-900/20 dark:text-blue-400";
      case "COMPLETED":
        return "bg-green-100 text-green-800 dark:bg-green-900/20 dark:text-green-400";
      case "REJECTED":
        return "bg-red-100 text-red-800 dark:bg-red-900/20 dark:text-red-400";
      case "ACCEPTED":
        return "bg-purple-100 text-purple-800 dark:bg-purple-900/20 dark:text-purple-400";
      default:
        return "bg-gray-100 text-gray-800 dark:bg-gray-900/20 dark:text-gray-400";
    }
  };

  // Format the status text
  const getStatusText = (status: string) => {
    switch (status) {
      case "IN_PROGRESS":
        return "In Progress";
      default:
        return status.charAt(0) + status.slice(1).toLowerCase();
    }
  };

  return (
    <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${getStatusStyles()}`}>
      {getStatusText(status)}
    </span>
  );
}

export default function FeatureRequests() {
  const { data: session } = useSession();
  const [featureRequests, setFeatureRequests] = useState<FeatureRequest[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [showForm, setShowForm] = useState(false);
  const [formData, setFormData] = useState({
    title: "",
    description: "",
  });
  const [filters, setFilters] = useState({
    status: "OPEN",
    view: "ALL", // ALL, MINE, VOTED
  });
  const [sortBy, setSortBy] = useState<SortOption>('votes');
  const [editingRequest, setEditingRequest] = useState(null);

  useEffect(() => {
    fetchFeatureRequests();
  }, [filters]);

  const fetchFeatureRequests = async () => {
    try {
      const params = new URLSearchParams();
      if (filters.status !== "ALL") params.append("status", filters.status);
      if (filters.view !== "ALL") params.append("view", filters.view);
      params.append("sort", sortBy);
      
      const response = await fetch(`/api/feature-requests?${params}`);
      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.message || "Failed to fetch feature requests");
      }

      setFeatureRequests(data.featureRequests);
    } catch (err) {
      setError("Failed to load feature requests");
    } finally {
      setLoading(false);
    }
  };

  const handleVote = async (id: string) => {
    if (!session) return;

    try {
      const response = await fetch(`/api/feature-requests/${id}/vote`, {
        method: "POST",
      });
      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.message);
      }

      // Refresh feature requests to update vote count
      fetchFeatureRequests();
    } catch (err) {
      setError("Failed to process vote");
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    try {
      const response = await fetch("/api/feature-requests", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(formData),
      });

      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.message);
      }

      // Reset form and refresh feature requests
      setFormData({ title: "", description: "" });
      setShowForm(false);
      fetchFeatureRequests();
    } catch (err) {
      setError("Failed to create feature request");
    }
  };

  const handleStatusUpdate = async (id: string, status: string) => {
    try {
      const response = await fetch(`/api/feature-requests/${id}/status`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ status }),
      });

      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.message);
      }

      // Refresh feature requests to update the status
      fetchFeatureRequests();
    } catch (err) {
      setError("Failed to update status");
    }
  };

  const handleEdit = async (updatedRequest) => {
    try {
      setError("");
      const response = await fetch(`/api/feature-requests/${editingRequest.id}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(updatedRequest),
      });

      if (!response.ok) {
        const data = await response.json();
        throw new Error(data.message || 'Failed to update feature request');
      }

      const updated = await response.json();
      setFeatureRequests(prev =>
        prev.map(req => req.id === updated.id ? updated : req)
      );
      setEditingRequest(null);
    } catch (error) {
      console.error('Error updating feature request:', error);
      setError(error.message);
    }
  };

  const handleDelete = async (requestId) => {
    try {
      const response = await fetch(`/api/feature-requests/${requestId}`, {
        method: 'DELETE',
      });

      if (!response.ok) {
        const data = await response.json();
        throw new Error(data.message || 'Failed to delete feature request');
      }

      setFeatureRequests(prev => 
        prev.filter(request => request.id !== requestId)
      );
    } catch (error) {
      console.error('Error deleting feature request:', error);
      alert(error.message);
    }
  };

  const getSortedRequests = () => {
    return [...featureRequests].sort((a, b) => {
      switch (sortBy) {
        case 'votes':
          return b.voteCount - a.voteCount;
        case 'newest':
          return new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime();
        case 'oldest':
          return new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime();
        default:
          return 0;
      }
    });
  };

  return (
    <DashboardLayout title="Feature Requests">
      <div className="space-y-6">
        {/* Filters */}
        <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
          <div className="flex items-center space-x-4">
            <select
              value={filters.status}
              onChange={(e) => setFilters(prev => ({ ...prev, status: e.target.value }))}
              className="px-3 py-2 bg-white dark:bg-github-dark-bg border border-github-border dark:border-github-dark-border rounded-md"
            >
              <option value="OPEN">Open</option>
              <option value="ALL">All Requests</option>
              <option value="ACCEPTED">Accepted</option>
              <option value="IN_PROGRESS">In Progress</option>
              <option value="COMPLETED">Completed</option>
              <option value="REJECTED">Rejected</option>
            </select>

            <select
              value={filters.view}
              onChange={(e) => setFilters(prev => ({ ...prev, view: e.target.value }))}
              className="px-3 py-2 bg-white dark:bg-github-dark-bg border border-github-border dark:border-github-dark-border rounded-md"
            >
              <option value="ALL">All Owners</option>
              <option value="MINE">My Requests</option>
              <option value="VOTED">Voted By Me</option>
            </select>

            <select
              value={sortBy}
              onChange={(e) => setSortBy(e.target.value as SortOption)}
              className="px-3 py-2 bg-white dark:bg-github-dark-bg border border-github-border dark:border-github-dark-border rounded-md"
            >
              <option value="votes">Most Votes</option>
              <option value="newest">Newest First</option>
              <option value="oldest">Oldest First</option>
            </select>
          </div>

          <button
            onClick={() => setShowForm(!showForm)}
            className="flex items-center px-4 py-2 
              bg-github-primary dark:bg-github-dark-accent 
              text-white rounded-md 
              hover:bg-opacity-90
              dark:border dark:border-github-dark-accent"
          >
            <FiPlus className="mr-2" />
            New Feature Request
          </button>
        </div>

        {/* New feature request form */}
        {showForm && (
          <form onSubmit={handleSubmit} className="bg-github-bg dark:bg-github-dark-hover p-6 rounded-lg border border-github-border dark:border-github-dark-border">
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium mb-1">Title</label>
                <input
                  type="text"
                  maxLength={100}
                  value={formData.title}
                  onChange={(e) => setFormData({ ...formData, title: e.target.value })}
                  className="w-full px-3 py-2 
                    bg-white dark:bg-github-dark-bg
                    text-gray-900 dark:text-white
                    border border-github-border dark:border-github-dark-border 
                    rounded-md
                    focus:outline-none focus:ring-2 
                    focus:ring-github-primary dark:focus:ring-github-dark-accent
                    placeholder:text-gray-400 dark:placeholder:text-gray-500"
                  required
                />
              </div>
              <div>
                <label className="block text-sm font-medium mb-1">Description</label>
                <textarea
                  maxLength={500}
                  value={formData.description}
                  onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                  className="w-full px-3 py-2 
                    bg-white dark:bg-github-dark-bg
                    text-gray-900 dark:text-white
                    border border-github-border dark:border-github-dark-border 
                    rounded-md
                    focus:outline-none focus:ring-2 
                    focus:ring-github-primary dark:focus:ring-github-dark-accent
                    placeholder:text-gray-400 dark:placeholder:text-gray-500"
                  rows={4}
                  required
                />
              </div>
              <div className="flex justify-end space-x-3">
                <button
                  type="button"
                  onClick={() => setShowForm(false)}
                  className="px-4 py-2 border border-github-border dark:border-github-dark-border rounded-md"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="px-4 py-2 
                    bg-github-primary dark:bg-github-dark-accent 
                    text-white rounded-md 
                    hover:bg-opacity-90
                    dark:border dark:border-github-dark-accent"
                >
                  Submit
                </button>
              </div>
            </div>
          </form>
        )}

        {/* Feature requests list */}
        <div className="space-y-4">
          {getSortedRequests().length === 0 ? (
            <p className="text-gray-500 dark:text-gray-400">No matching requests found</p>
          ) : (
            getSortedRequests().map((request) => (
              <FeatureRequestCard
                key={request.id}
                request={request}
                onVote={handleVote}
                onEdit={() => setEditingRequest(request)}
                onDelete={() => setEditingRequest(request)}
              />
            ))
          )}
        </div>
      </div>

      {/* Edit Modal/Form */}
      {editingRequest && (
        <EditFeatureRequestModal
          request={editingRequest}
          onClose={() => setEditingRequest(null)}
          onSave={handleEdit}
          onDelete={handleDelete}
        />
      )}
    </DashboardLayout>
  );
} 