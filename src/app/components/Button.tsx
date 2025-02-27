import React from 'react';

type ButtonProps = {
  onClick: () => void;
  disabled?: boolean;
  className?: string;
  children: React.ReactNode;
};

const Button: React.FC<ButtonProps> = ({ onClick, disabled, className, children }) => {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className={`flex items-center space-x-2 px-3 py-2 rounded-md 
        ${disabled ? "opacity-50 cursor-not-allowed" : ""}
        ${className} 
        ${disabled ? "" : "border border-yellow-500"}`}
    >
      {children}
    </button>
  );
};

export default Button; 