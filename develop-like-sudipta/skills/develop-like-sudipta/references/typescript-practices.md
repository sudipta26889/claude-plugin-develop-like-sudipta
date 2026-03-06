# TypeScript/JavaScript Best Practices

## Tooling Stack (2025)

| Tool | Purpose |
|------|---------|
| **TypeScript strict mode** | Static type safety |
| **ESLint + typescript-eslint** | Linting (flat config) |
| **Prettier** | Formatting |
| **Zod** | Runtime validation at boundaries |
| **pnpm** | Package management (Thoughtworks Radar: Adopt) |
| **Vitest** | Testing (Vite-native, Jest drop-in) |

## Banned Legacy Packages (New Projects)

| Don't Use | Use Instead | Why |
|---|---|---|
| `moment` / `moment-timezone` | `dayjs` or `Temporal` API | Moment deprecated, 70KB |
| `enzyme` | `@testing-library/react` | Enzyme abandoned |
| `tslint` | `eslint + typescript-eslint` | TSLint deprecated 2019 |
| `jest` (new projects) | `vitest` | Vite-native, faster, ESM-first |
| `request` (npm) | `undici` / native `fetch` | `request` deprecated 2020 |
| `lodash` (full import) | `lodash-es` or native methods | Tree-shake or avoid entirely |
| `create-react-app` | `vite` | CRA abandoned |
| `require()` / CommonJS | ES Modules (`import`) | CJS is legacy in new code |
| `express` (new projects) | Research `hono` / `fastify` first | Express valid but verify need |
| `webpack` (new projects) | `vite` / `turbopack` | Faster, simpler config |

**Exception:** Existing codebases — don't rewrite working deps. Apply to NEW additions only.
**Rule:** Before ANY `pnpm add` / `npm install`, run Package Selection Gate (Pillar 10 in SKILL.md).

## tsconfig.json (Strict Mode)

```json
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "forceConsistentCasingInFileNames": true,
    "exactOptionalPropertyTypes": true,
    "moduleResolution": "bundler",
    "module": "ESNext",
    "target": "ES2022",
    "isolatedModules": true,
    "verbatimModuleSyntax": true
  }
}
```

## ESLint (Flat Config)

```javascript
import eslint from "@eslint/js";
import tseslint from "typescript-eslint";

export default tseslint.config(
  eslint.configs.recommended,
  ...tseslint.configs.strictTypeChecked,
  {
    languageOptions: { parserOptions: { projectService: true } },
    rules: {
      "@typescript-eslint/no-explicit-any": "error",
      "@typescript-eslint/no-unused-vars": ["error", { argsIgnorePattern: "^_" }],
      "@typescript-eslint/no-require-imports": "error",
      "@typescript-eslint/prefer-nullish-coalescing": "error",
      "@typescript-eslint/prefer-optional-chain": "error",
    },
  },
);
```

## Zod at Runtime Boundaries

```typescript
import { z } from "zod";

const CreateUserSchema = z.object({
  email: z.string().email(),
  name: z.string().min(2).max(100),
  role: z.enum(["admin", "member", "viewer"]),
});
type CreateUserInput = z.infer<typeof CreateUserSchema>;

// Environment variable validation
const EnvSchema = z.object({
  DATABASE_URL: z.string().url(),
  JWT_SECRET: z.string().min(32),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  NODE_ENV: z.enum(["development", "staging", "production"]).default("development"),
});
export const env = EnvSchema.parse(process.env);
```

## ES Modules (Standard)

```json
{ "type": "module", "packageManager": "pnpm@9.0.0" }
```

```typescript
// ✅ ES Modules
import { createServer } from "node:http";
// ❌ CommonJS — banned by no-require-imports rule
```

## Bundle Optimization

```typescript
// ❌ Barrel files defeat tree shaking
export { Button } from "./Button";  // Importing ANY loads ALL

// ✅ Import directly from source
import { Button } from "@/components/Button";

// ✅ Dynamic imports for code splitting
const AdminPanel = lazy(() => import("./AdminPanel"));

// ✅ package.json: { "sideEffects": false }
```

## React Patterns (Functional Only)

```typescript
interface UserCardProps {
  user: User;
  onEdit?: (user: User) => void;
}

export function UserCard({ user, onEdit }: UserCardProps) {
  const { data, isLoading } = useUser(user.id);
  if (isLoading) return <UserCardSkeleton />;
  return (
    <article className="rounded-lg border p-4">
      <h2>{user.name}</h2>
      {onEdit && <button onClick={() => onEdit(user)}>Edit</button>}
    </article>
  );
}

// Custom hook — reusable data fetching
function useUser(userId: string) {
  return useQuery({
    queryKey: ["user", userId],
    queryFn: () => api.users.get(userId),
    staleTime: 5 * 60 * 1000,
  });
}
```

## pnpm Workspace (Monorepo)

```yaml
# pnpm-workspace.yaml
packages: ["apps/*", "packages/*"]
```

```
monorepo/
├── apps/ (web/, api/)
├── packages/ (shared/, ui/)
├── pnpm-workspace.yaml
├── pnpm-lock.yaml (commit this)
└── turbo.json
```

## TypeScript-Specific Rules

| Rule | Standard |
|------|----------|
| Formatter | Prettier |
| Linter | ESLint + typescript-eslint |
| Type checker | tsc (strict: true) |
| Runtime validation | Zod at boundaries |
| Package manager | pnpm |
| Lockfile | pnpm-lock.yaml (commit) |
| CI install | `pnpm install --frozen-lockfile` |
| Ban in production | `console.log` |
| Test runner | Vitest |
| Ban | `any` type, `@ts-ignore` |
