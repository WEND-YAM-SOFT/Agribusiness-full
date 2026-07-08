# AgriBusiness Mobile (Flutter)

This folder is prepared for:

1. GitHub source control
2. Supabase database/auth setup
3. Vercel deployment for Flutter Web frontend only

## 1) Push to GitHub

From the `mobile` folder:

```powershell
git init
git add .
git commit -m "chore: prepare flutter web for github + supabase + vercel"
git branch -M main
git remote add origin <YOUR_GITHUB_REPO_URL>
git push -u origin main
```

## 2) Supabase setup (starter)

1. Create a Supabase project.
2. Open SQL Editor.
3. Run `supabase/schema_starter.sql`.
4. Create your first company in `entreprises`.
5. Create your auth user.
6. Insert a row in `profiles` with that user id and company id.

Notes:

1. The schema is mono-company friendly today, multi-company ready for later.
2. Row Level Security is enabled for key tables.

## 3) Vercel deployment (frontend only)

Use Vercel to host only Flutter Web static files.

### Project settings

1. Import the GitHub repository in Vercel.
2. Set Root Directory to `mobile`.
3. Framework preset: `Other`.

### Build settings

Build command:

```bash
flutter pub get && flutter build web --release --dart-define=API_BASE_URL=$API_BASE_URL
```

Output directory:

```text
build/web
```

### Environment variables (Vercel)

Add at least:

1. `API_BASE_URL` (example: `https://your-api-domain.com/api`)

Optional for migration to direct Supabase client usage:

1. `SUPABASE_URL`
2. `SUPABASE_ANON_KEY`

### SPA routing

`vercel.json` is included to rewrite all routes to `index.html`.

## 4) Local web build test

```powershell
flutter pub get
flutter build web --release --dart-define=API_BASE_URL=http://localhost:5000/api
cd build/web
npx serve -l 8091
```

## 5) Security checklist

1. Never commit secrets.
2. Keep only public keys in frontend (`SUPABASE_ANON_KEY`).
3. Keep service keys only in secure backend environments.

