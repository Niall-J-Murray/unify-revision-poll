/** @type {import('tailwindcss').Config} */
module.exports = {
  darkMode: 'class',
  content: [
    './src/pages/**/*.{js,ts,jsx,tsx,mdx}',
    './src/components/**/*.{js,ts,jsx,tsx,mdx}',
    './src/app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        // GitHub-inspired colors with royal blue
        github: {
          // Light mode
          bg: '#ffffff',
          fg: '#24292f',
          border: '#d0d7de',
          primary: '#1a56db', // Royal blue shade
          secondary: '#6e7781',
          accent: '#1a56db', // Royal blue shade
          hover: '#f6f8fa',
          
          // Dark mode
          'dark-bg': '#0d1117',
          'dark-fg': '#c9d1d9',
          'dark-border': '#30363d',
          'dark-primary': '#4d7eff', // Royal blue shade for dark mode
          'dark-secondary': '#8b949e',
          'dark-accent': '#2563eb', // Royal blue shade for dark mode
          'dark-hover': '#161b22',
        },
      },
    },
  },
  plugins: [],
} 