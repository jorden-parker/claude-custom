This is a [Next.js](https://nextjs.org) project bootstrapped with [`create-next-app`](https://nextjs.org/docs/app/api-reference/cli/create-next-app).

## Access token

Every route is behind the token gate in `src/proxy.ts`. A request is served only when it carries the value of `PR_REVIEW_TOKEN`, either as the `token` query parameter (the gate then sets an `HttpOnly`, `SameSite=Strict` cookie and redirects to the same page without the parameter) or as that cookie. With `PR_REVIEW_TOKEN` unset, every request gets `401`.

- `claude-ollama reviews` makes a new token on every launch and prints the tokened link.
- `pnpm demo --serve` makes its own token and prints its tokened link.
- `pnpm dev` and `pnpm start` need the variable exported first:

```bash
export PR_REVIEW_TOKEN="$(openssl rand -hex 24)"
pnpm dev
```

Then open `http://localhost:3000/?token=<token>`.

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

## Learn More

To learn more about Next.js, take a look at the following resources:

- [Next.js Documentation](https://nextjs.org/docs) - learn about Next.js features and API.
- [Learn Next.js](https://nextjs.org/learn) - an interactive Next.js tutorial.

You can check out [the Next.js GitHub repository](https://github.com/vercel/next.js) - your feedback and contributions are welcome!

## Deploy on Vercel

The easiest way to deploy your Next.js app is to use the [Vercel Platform](https://vercel.com/new?utm_medium=default-template&filter=next.js&utm_source=create-next-app&utm_campaign=create-next-app-readme) from the creators of Next.js.

Check out our [Next.js deployment documentation](https://nextjs.org/docs/app/building-your-application/deploying) for more details.
