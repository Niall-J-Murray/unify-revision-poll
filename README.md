This is a [Next.js](https://nextjs.org) project bootstrapped with [`create-next-app`](https://nextjs.org/docs/app/api-reference/cli/create-next-app).

## Getting Started

First, run the development server:

```bash
npm run dev
# or
yarn dev
# or
pnpm dev
# or
bun dev
```

Open [http://localhost:3000](http://localhost:3000) with your browser to see the result.

You can start editing the page by modifying `app/page.tsx`. The page auto-updates as you edit the file.

This project uses [`next/font`](https://nextjs.org/docs/app/building-your-application/optimizing/fonts) to automatically optimize and load [Geist](https://vercel.com/font), a new font family for Vercel.

## Testing

This project uses Jest for testing. The tests are organized in the `src/__tests__` directory, with subdirectories for different types of tests:

- `api`: Tests for API routes
- `components`: Tests for React components
- `helpers`: Helper functions and mocks for tests

### Running Tests

You can run the tests using the following commands:

```bash
# Run all tests
npm test

# Run tests in watch mode (re-run on file changes)
npm run test:watch

# Run tests with coverage report
npm run test:coverage

# Run only API tests
npm run test:api

# Run only component tests
npm run test:components

# Run only tests for changed files
npm run test:changed

# Update snapshots
npm run test:update
```

### Writing Tests

#### API Tests

API tests should be placed in the `src/__tests__/api` directory, with a structure that mirrors the API routes. For example, tests for `/api/user/profile` should be in `src/__tests__/api/user/profile.test.ts`.

We provide helper functions in `src/__tests__/helpers/api-test-helpers.ts` to make it easier to test API routes:

```typescript
// Example API test
import { testApiEndpoint } from "../../helpers/api-test-helpers";
import { GET, POST } from "@/app/api/some-route/route";

describe("Some API Route", () => {
  testApiEndpoint("should return data successfully", GET, {
    method: "GET",
    authenticated: true,
    expectedStatus: 200,
    expectedData: { success: true },
  });
});
```

#### Component Tests

Component tests should be placed in the `src/__tests__/components` directory. We use React Testing Library for testing components.

```typescript
// Example component test
import { render, screen } from "@testing-library/react";
import MyComponent from "@/app/components/MyComponent";

describe("MyComponent", () => {
  it("renders correctly", () => {
    render(<MyComponent />);
    expect(screen.getByText("Some Text")).toBeInTheDocument();
  });
});
```

### Mocks

Common mocks are provided in the `src/__tests__/helpers` directory:

- `prisma-mock.ts`: Mocks for Prisma ORM
- `email-service-mock.ts`: Mocks for email service
- `api-test-helpers.ts`: Helpers for testing API routes

## Learn More

To learn more about Next.js, take a look at the following resources:

- [Next.js Documentation](https://nextjs.org/docs) - learn about Next.js features and API.
- [Learn Next.js](https://nextjs.org/learn) - an interactive Next.js tutorial.

You can check out [the Next.js GitHub repository](https://github.com/vercel/next.js) - your feedback and contributions are welcome!

## Deploy on Vercel

The easiest way to deploy your Next.js app is to use the [Vercel Platform](https://vercel.com/new?utm_medium=default-template&filter=next.js&utm_source=create-next-app&utm_campaign=create-next-app-readme) from the creators of Next.js.

Check out our [Next.js deployment documentation](https://nextjs.org/docs/app/building-your-application/deploying) for more details.
