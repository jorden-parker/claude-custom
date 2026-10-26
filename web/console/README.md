This is a [Next.js](https://nextjs.org) project bootstrapped with
[`create-next-app`](https://nextjs.org/docs/app/api-reference/cli/create-next-app).

## Access token

Every route is behind the token gate in `src/proxy.ts`. The gate reads the token
from the file named by `CONSOLE_TOKEN_FILE`. A request is served only when it
carries that token, either as the `token` query parameter (the gate then sets an
`HttpOnly`, `SameSite=Strict` cookie named `console_token` and redirects to the
same page without the parameter) or as that cookie. With `CONSOLE_TOKEN_FILE`
unset, or the file missing, every request gets `401`.

- `claude-ollama ui` and `claude-ollama reviews` make a new token on every
  launch, keep it in `$CLAUDE_CONSOLE_STATE_DIR/tokens/<port>` (default
  `~/.local/share/claude-custom/console/tokens/<port>`, mode `0600`, in a folder
  the `claude-ollama` sandbox cannot read), and print the tokened link.
- `pnpm demo --serve` makes its own token in a `0600` file in its demo folder
  and prints its tokened link.
- `pnpm dev` and `pnpm start` need the file written and the variable exported
  first:

```bash
umask 077; openssl rand -hex 24 > /tmp/console-token
export CONSOLE_TOKEN_FILE=/tmp/console-token
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

Open [http://localhost:3000](http://localhost:3000) with your browser to see the
result.

You can start editing the page by modifying `app/page.tsx`. The page
auto-updates as you edit the file.

This project uses
[`next/font`](https://nextjs.org/docs/app/building-your-application/optimizing/fonts)
to automatically optimize and load [Geist](https://vercel.com/font), a new font
family for Vercel.

## Learn More

To learn more about Next.js, take a look at the following resources:

- [Next.js Documentation](https://nextjs.org/docs) - learn about Next.js
  features and API.
- [Learn Next.js](https://nextjs.org/learn) - an interactive Next.js tutorial.

You can check out
[the Next.js GitHub repository](https://github.com/vercel/next.js) - your
feedback and contributions are welcome!

## Deploy on Vercel

The easiest way to deploy your Next.js app is to use the
[Vercel Platform](https://vercel.com/new?utm_medium=default-template&filter=next.js&utm_source=create-next-app&utm_campaign=create-next-app-readme)
from the creators of Next.js.

Check out our
[Next.js deployment documentation](https://nextjs.org/docs/app/building-your-application/deploying)
for more details.
