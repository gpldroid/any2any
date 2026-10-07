# Any2Any

Production-oriented rebuild of XConvertPro into a Next.js + Supabase + ImageMagick application.

## Reverse-engineered source

XConvertPro is a Laravel 10 application on PHP 8.1+ using Filament 3, Livewire 3, Sanctum, Spatie Laravel Settings, Eloquent Viewable, SEO Tools, Laravel Localization and Imagick. The conversion core is split into App\\Services\\Converter and App\\Services\\Processor; uploads are handled by App\\Livewire\\Uploader. The original database contains users, settings, pages, posts, views, view counters and conversion counters.

This rebuild preserves the important product behavior rather than copying generated/vendor assets: 24 image output formats, upload/convert/download flow, converter catalog, authentication, admin access control, content/settings tables and conversion analytics.

## Architecture

- Next.js App Router / React / TypeScript
- Supabase Auth + PostgreSQL + RLS + Realtime
- ImageMagick + Ghostscript + HEIF/WebP/JPEG/PNG/TIFF delegates inside Docker
- Server-side conversion API; uploaded files are temporary and deleted after processing
- GitHub Actions for typecheck, production build and Docker validation

## Supabase

Set NEXT_PUBLIC_SUPABASE_URL to https://upajzbaeuwzbhxfebzvi.supabase.co and provide the project's publishable key. Run supabase/migrations/20261007000000_any2any.sql in the target Supabase project.

The migration explicitly grants the required Data API roles because Supabase changed public-schema exposure defaults in 2026, while RLS remains enabled.

The connected Supabase account currently does not expose project ref upajzbaeuwzbhxfebzvi, so this session committed the migration but could not execute it remotely.

## Admin

Create a user in Supabase Auth. The profile trigger creates public.profiles. Then, from a trusted SQL session, promote the user:

update public.profiles set role='admin' where id='USER_UUID';

Never put a service-role key in browser code or in a NEXT_PUBLIC_* variable.

## Local run

1. npm install
2. Copy .env.example to .env.local and fill the publishable key.
3. npm run dev
4. Production: npm run build && npm start

The Docker image installs the native ImageMagick dependencies required by the conversion engine.

## Production hardening

- Add rate limiting and per-IP quotas.
- Add MIME/signature validation and strict ImageMagick policy restrictions.
- Use object storage plus background jobs for large files.
- Add antivirus/content scanning for arbitrary public uploads.
- Add integration tests for every format/delegate available in the deployment image.
