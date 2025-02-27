import React, { useState } from "react";
import { FiEye, FiEyeOff } from "react-icons/fi";

type InputProps = {
  id: string;
  name: string;
  type: string;
  label: string;
  value: string;
  onChange: (e: React.ChangeEvent<HTMLInputElement>) => void;
  required?: boolean;
  placeholder?: string;
  error?: string;
};

export default function Input({
  id,
  name,
  type,
  label,
  value,
  onChange,
  required = false,
  placeholder = "",
  error,
}: InputProps) {
  const [showPassword, setShowPassword] = useState(false);
  
  const togglePasswordVisibility = () => {
    setShowPassword(!showPassword);
  };
  
  // Determine the actual input type
  const inputType = type === "password" 
    ? (showPassword ? "text" : "password") 
    : type;

  return (
    <div className="mb-4">
      <label
        htmlFor={id}
        className="block text-sm font-medium mb-1 text-github-fg dark:text-github-dark-fg"
      >
        {label} {required && <span className="text-red-500 dark:text-red-400">*</span>}
      </label>
      <div className="relative">
        <input
          id={id}
          name={name}
          type={inputType}
          value={value}
          onChange={onChange}
          required={required}
          placeholder={placeholder}
          className={`w-full px-3 py-2 border ${
            error ? "border-red-300 dark:border-red-700" : "border-github-border dark:border-github-dark-border"
          } bg-github-bg dark:bg-github-dark-bg text-github-fg dark:text-github-dark-fg rounded-md shadow-sm focus:outline-none focus:ring-2 focus:ring-github-primary dark:focus:ring-github-dark-primary focus:border-github-primary dark:focus:border-github-dark-primary transition-colors ${
            type === "password" ? "pr-10" : ""
          }`}
        />
        {type === "password" && (
          <button
            type="button"
            className="absolute inset-y-0 right-0 pr-3 flex items-center text-github-secondary dark:text-github-dark-secondary hover:text-github-primary dark:hover:text-github-dark-primary"
            onClick={togglePasswordVisibility}
          >
            {showPassword ? (
              <FiEyeOff className="h-5 w-5" aria-hidden="true" />
            ) : (
              <FiEye className="h-5 w-5" aria-hidden="true" />
            )}
          </button>
        )}
      </div>
      {error && <p className="mt-1 text-sm text-red-600 dark:text-red-400">{error}</p>}
    </div>
  );
} 