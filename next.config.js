/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  swcMinify: true,
  // Disable SWC as replacement for Babel because of custom Babel configuration
  experimental: {
    // Disable SWC as replacement for Babel
    forceSwcTransforms: false,
  },
  // Configure webpack to handle transpilation
  webpack: (config, { isServer }) => {
    // Add any webpack configurations if needed
    return config;
  },
};

module.exports = nextConfig;
