# Multi-stage build for Next.js application with Prisma

# ==== DEPENDENCIES STAGE ====
FROM node:18-alpine AS deps
WORKDIR /app

# Install dependencies needed for Prisma and build
RUN apk add --no-cache libc6-compat openssl
COPY package.json package-lock.json* ./
# Copy Prisma schema files before npm ci
COPY prisma ./prisma/
RUN npm ci

# ==== BUILDER STAGE ====
FROM node:18-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Generate Prisma client
RUN npx prisma generate

# Build application
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

# ==== PRODUCTION STAGE ====
FROM node:18-alpine AS runner
WORKDIR /app

RUN apk add --no-cache openssl

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# Create a non-root user
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

# Copy necessary files from builder
# Check if standalone output exists
RUN mkdir -p .next/standalone .next/static
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/prisma ./prisma
COPY --from=builder --chown=nextjs:nodejs /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=builder --chown=nextjs:nodejs /app/node_modules/@prisma ./node_modules/@prisma

# Copy the built application
COPY --from=builder --chown=nextjs:nodejs /app/.next ./.next
COPY --from=builder --chown=nextjs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nextjs:nodejs /app/package.json ./package.json

# Set correct permissions
# Install psql client *before* switching user
# RUN apk add --no-cache postgresql15-client # Keep commented out unless needed for future debugging
USER nextjs

# Expose the port the app runs on
EXPOSE 3000

# Add health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 CMD wget -qO- http://localhost:3000/api/health || exit 1

# Run database migrations, then seed the database, and then start the application
# Use semicolons and echo for better debugging
CMD ["sh", "-c", "echo 'Attempting migrations...' && npx prisma migrate deploy; echo 'Attempting seeding...' && npx prisma db seed; echo 'Starting application...' && npm run start"] 