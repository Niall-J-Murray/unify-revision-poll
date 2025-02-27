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
          primary: '#0969DA', // Darker blue
          secondary: '#57606a',
          accent: '#DAA520', // Dark yellow accent
          hover: '#f3f4f6',
          
          // Dark mode
          'dark-bg': '#0d1117',
          'dark-fg': '#c9d1d9',
          'dark-border': '#30363d',
          'dark-primary': '#1F6FEB', // Darker blue for dark mode
          'dark-secondary': '#8b949e',
          'dark-accent': '#B8860B', // Darker yellow accent for dark mode
          'dark-hover': '#161b22',
        },
        'github-dark': {
          'primary': '#1F6FEB', // Darker blue for dark mode
          'secondary': '#8b949e',
          'hover': '#161b22',
          'border': '#30363d',
          'bg': '#0d1117',
          'fg': '#c9d1d9',
          'accent': '#B8860B', // Darker yellow accent for dark mode
        },
      },
    },
  },
  plugins: [],
} 