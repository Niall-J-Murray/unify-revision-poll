module.exports = {
  presets: [
    [
      "@babel/preset-env",
      {
        targets: { node: "current" },
        modules: "commonjs",
      },
    ],
    "@babel/preset-typescript",
  ],
  env: {
    test: {
      // Jest-specific configurations should only be applied in test environment
      transformIgnorePatterns: ["node_modules/(?!(@auth|next|next-auth)/)"],
    },
  },
};
