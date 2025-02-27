import { useState } from "react";
import { FiTrash2 } from "react-icons/fi";

type EditFeatureRequestModalProps = {
  request: {
    id: string;
    title: string;
    description: string;
  };
  onClose: () => void;
  onSave: (updatedRequest: { title: string; description: string }) => Promise<void>;
  onDelete: (id: string) => Promise<void>;
};

export default function EditFeatureRequestModal({
  request,
  onClose,
  onSave,
  onDelete,
}: EditFeatureRequestModalProps) {
  const [formData, setFormData] = useState({
    title: request.title,
    description: request.description,
  });
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [error, setError] = useState("");

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSubmitting(true);
    setError("");

    try {
      await onSave(formData);
      onClose();
    } catch (err) {
      setError("Failed to update feature request");
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleDelete = async () => {
    if (window.confirm("Are you sure you want to delete this feature request?")) {
      setIsDeleting(true);
      setError("");

      try {
        await onDelete(request.id);
        onClose();
      } catch (err) {
        setError("Failed to delete feature request");
      } finally {
        setIsDeleting(false);
      }
    }
  };

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div className="bg-github-bg dark:bg-github-dark-hover rounded-lg shadow-xl max-w-2xl w-full mx-4">
        <div className="p-6">
          <div className="flex justify-between items-start mb-4">
            <h2 className="text-xl font-semibold">Edit Feature Request</h2>
            <button
              onClick={handleDelete}
              disabled={isDeleting || isSubmitting}
              className="p-2 text-red-600 hover:text-red-700 dark:text-red-400 dark:hover:text-red-300 rounded-md hover:bg-red-50 dark:hover:bg-red-900/20"
              title="Delete request"
            >
              <FiTrash2 className="h-5 w-5" />
            </button>
          </div>

          {error && (
            <div className="mb-4 text-red-600 dark:text-red-400">{error}</div>
          )}

          <form onSubmit={handleSubmit} className="space-y-4">
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
                  focus:ring-github-primary dark:focus:ring-github-dark-accent"
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
                  focus:ring-github-primary dark:focus:ring-github-dark-accent"
                rows={4}
                required
              />
            </div>
            <div className="flex justify-end space-x-3 pt-4">
              <button
                type="button"
                onClick={onClose}
                className="px-4 py-2 border border-github-border dark:border-github-dark-border rounded-md hover:bg-github-hover dark:hover:bg-github-dark-hover"
                disabled={isSubmitting || isDeleting}
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
                disabled={isSubmitting || isDeleting}
              >
                {isSubmitting ? "Saving..." : "Save Changes"}
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
} 