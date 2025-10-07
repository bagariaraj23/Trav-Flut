import { z } from 'zod';

// Define environment schema with Zod for validation
const envSchema = z.object({
    // Node environment
    NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),

    // Add your environment variables here
    // Example:
    // DATABASE_URL: z.string().url(),
    // JWT_SECRET: z.string().min(1),
});

// Parse and validate environment variables
const parsed = envSchema.safeParse(process.env);

if (!parsed.success) {
    console.error(
        '❌ Invalid environment variables:',
        JSON.stringify(parsed.error.format(), null, 2),
    );
    process.exit(1);
}

// Export validated and typed env object
export const ENV = parsed.data as Readonly<z.infer<typeof envSchema>>;

// Log environment status in development
if (ENV.NODE_ENV === 'development') {
    console.log('[Next.js] Environment loaded:', {
        NODE_ENV: ENV.NODE_ENV
    });
}