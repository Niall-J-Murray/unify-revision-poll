module.exports = {
  presets: [
    ['@babel/preset-env', { 
      targets: { node: 'current' },
      modules: 'commonjs'
    }],
    '@babel/preset-typescript',
  ],
  transformIgnorePatterns: [
    'node_modules/(?!(@auth|next|next-auth)/)'
  ]
};