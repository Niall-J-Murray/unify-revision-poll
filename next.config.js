/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Configure webpack to handle transpilation
  webpack: (config, { isServer }) => {
    // Add any webpack configurations if needed
    return config;
  },
};

module.exports = nextConfig;
