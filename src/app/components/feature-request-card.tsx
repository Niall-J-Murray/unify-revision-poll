import { useState } from "react";
import { FiThumbsUp, FiEdit2, FiUser, FiClock } from "react-icons/fi";
import { useSession } from "next-auth/react";

export default function FeatureRequestCard({ request, onVote, onEdit }) {
  const { data: session } = useSession();
  
  const isOwner = session?.user?.id === request.userId;
  const hasVoted = request.votes?.some(vote => vote.userId === session?.user?.id);
  const canEditOrDelete = isOwner && request.voteCount === 0;

  const getVoteButtonStyles = () => {
    if (hasVoted) {
      return "bg-github-primary text-white hover:bg-opacity-90";
    }
    if (isOwner) {
      return "bg-gray-100 text-gray-500 dark:bg-gray-800 dark:text-gray-400 cursor-not-allowed";
    }
    return "hover:bg-github-hover dark:hover:bg-github-dark-hover";
  };

  const getVoteButtonTitle = () => {
    if (isOwner) return "You cannot vote on your own request";
    if (hasVoted) return "Remove your vote";
    return "Vote for this request";
  };

  return (
    <div className="bg-github-bg dark:bg-github-dark-hover rounded-lg shadow-sm border border-github-border dark:border-github-dark-border p-6">
      <div className="flex flex-col space-y-4">
        {/* Header: Title and Status */}
        <div className="flex justify-between items-start">
          <h3 className="text-lg font-medium text-github-fg dark:text-github-dark-fg">
            {request.title}
          </h3>
          <div className="flex flex-col items-end space-y-1">
            <StatusBadge status={request.status} />
            <span className="text-xs text-github-secondary dark:text-github-dark-secondary">
              #{request.id}
            </span>
          </div>
        </div>

        {/* Description */}
        <div className="text-github-secondary dark:text-github-dark-secondary">
          {request.description}
        </div>

        {/* Actions and Meta */}
        <div className="flex justify-between items-end">
          {/* Vote and Edit/Delete buttons */}
          <div className="flex items-center space-x-2">
            <button
              onClick={() => onVote(request.id)}
              className={`flex items-center space-x-1 px-3 py-1 rounded-md ${getVoteButtonStyles()}`}
              disabled={isOwner}
              title={getVoteButtonTitle()}
            >
              <FiThumbsUp 
                className={`h-4 w-4 ${hasVoted ? 'fill-current' : ''}`} 
              />
              <span>{request.voteCount}</span>
            </button>

            {/* Edit/Delete buttons - only show if user is owner and no votes */}
            {canEditOrDelete && (
              <button
                onClick={() => onEdit(request)}
                className="p-2 text-github-secondary hover:text-github-fg dark:text-github-dark-secondary dark:hover:text-github-dark-fg rounded-md hover:bg-github-hover dark:hover:bg-github-dark-hover"
                title="Edit request"
              >
                <FiEdit2 className="h-4 w-4" />
              </button>
            )}
          </div>

          {/* Creator and Date */}
          <div className="flex items-center space-x-4 text-sm text-github-secondary dark:text-github-dark-secondary">
            <div className="flex items-center">
              <FiUser className="mr-1" />
              <span>{request.user.name || request.user.email.split('@')[0]}</span>
            </div>
            <div className="flex items-center">
              <FiClock className="mr-1" />
              <span>{new Date(request.createdAt).toLocaleDateString()}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function StatusBadge({ status }) {
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

  return (
    <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${getStatusStyles()}`}>
      {status === "IN_PROGRESS" ? "In Progress" : status.charAt(0) + status.slice(1).toLowerCase()}
    </span>
  );
} 