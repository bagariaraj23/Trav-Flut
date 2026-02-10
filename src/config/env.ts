// Backend Environment Configuration
export const config = {
  // API Configuration
  apiBaseUrl:
    process.env.API_BASE_URL ||
    process.env.NEXT_PUBLIC_API_BASE_URL ||
    "http://localhost:3000/api",
  publicApiBaseUrl:
    process.env.NEXT_PUBLIC_API_BASE_URL || "http://localhost:3000/api",

  // Server Configuration
  nodeEnv: process.env.NODE_ENV || "development",

  // Database
  databaseUrl: process.env.DATABASE_URL || "",

  // JWT Configuration
  jwtSecret: process.env.JWT_SECRET || "fallback-secret-change-in-production",
  jwtRefreshSecret:
    process.env.JWT_REFRESH_SECRET ||
    "fallback-refresh-secret-change-in-production",

  // Email Configuration
  sendGridApiKey: process.env.SENDGRID_API_KEY || "",
  fromEmail: process.env.FROM_EMAIL || "noreply@tripthread.com",

  // CORS Configuration
  allowedOrigins: process.env.ALLOWED_ORIGINS?.split(",") || [
    "http://localhost:3000",
    "http://localhost:3001",
    "http://127.0.0.1:3000",
    "http://127.0.0.1:3001",
  ],

  // Password Reset Configuration
  passwordResetTtlMinutes: parseInt(
    process.env.PASSWORD_RESET_TTL_MINUTES || "15"
  ),

  appResetWebUrl: process.env.APP_RESET_WEB_URL || "https://app.tripthread.com/reset",
  appScheme: process.env.APP_SCHEME || "travello",

  // Google OAuth
  googleOAuthClientId: process.env.GOOGLE_CLIENT_ID || "",

  // Security Configuration
  bcryptRounds: 12,

  // Rate Limiting
  rateLimitMaxRequests: 100,
  rateLimitWindowMs: 60000, // 1 minute
};

export default config;
