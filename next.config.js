/** @type {import('next').NextConfig} */
import 'dotenv/config';

const nextConfig = {
  // jsonwebtoken / bcryptjs use dynamic requires; bundling them for RSC causes
  // "TypeError: __webpack_require__.nmd is not a function" on API routes.
  serverExternalPackages: ["jsonwebtoken", "bcryptjs"],
  // instrumentationHook is now available by default in Next.js 15, no need to enable it
  env: {
    ENABLE_SCHEDULER: process.env.ENABLE_SCHEDULER,
    NEXT_PUBLIC_API_BASE_URL: process.env.NEXT_PUBLIC_API_BASE_URL,
    NEXT_PUBLIC_APP_WEB_URL: process.env.NEXT_PUBLIC_APP_WEB_URL
  },
  images: {
    remotePatterns: [
      {
        protocol: 'https',
        hostname: 'storage.googleapis.com',
        port: '',
        pathname: '/u/**'
      }
    ]
  },
  // CORS configuration for development
  async headers() {
    const allowedOrigins = process.env.ALLOWED_ORIGINS?.split(',') || [
      'http://localhost:3000',
      'http://localhost:3001',
      'http://127.0.0.1:3000',
      'http://127.0.0.1:3001'
    ];

    return [
      {
        // Apple requires application/json (not octet-stream) for Universal Links.
        source: '/.well-known/apple-app-site-association',
        headers: [
          { key: 'Content-Type', value: 'application/json' },
          { key: 'Cache-Control', value: 'public, max-age=3600' },
        ],
      },
      {
        source: '/.well-known/assetlinks.json',
        headers: [
          { key: 'Content-Type', value: 'application/json' },
          { key: 'Cache-Control', value: 'public, max-age=3600' },
        ],
      },
      {
        source: '/api/:path*',
        headers: [
          {
            // Browsers accept only one origin. Prefer the first configured origin;
            // route-level withCors can refine per request when wired.
            key: 'Access-Control-Allow-Origin',
            value: allowedOrigins[0] || '*'
          },
          {
            key: 'Access-Control-Allow-Methods',
            value: 'GET, POST, PUT, DELETE, OPTIONS'
          },
          {
            key: 'Access-Control-Allow-Headers',
            value: 'Content-Type, Authorization'
          },
          {
            key: 'Access-Control-Allow-Credentials',
            value: 'true'
          }
        ]
      }
    ];
  }
}

export default nextConfig;
