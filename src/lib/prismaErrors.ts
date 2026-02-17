/**
 * Handles Prisma unique constraint violation errors (P2002)
 * Provides user-friendly error messages for unique constraint violations
 * 
 * @param error - The Prisma error object
 * @param fieldMap - Map of database field names to friendly display names
 * @returns User-friendly error message or null if not a unique constraint error
 * 
 */
export function handlePrismaUniqueError(
    error: any,
    fieldMap: Record<string, string> = {}
): string | null {
    if (!error || error.code !== "P2002") {
        return null;
    }

    const target = error.meta?.target ?? [];
    
    // Handle composite unique constraints (e.g., [followerId, followeeId])
    if (Array.isArray(target) && target.length > 1) {
        // For composite constraints, provide a generic message or use a special key
        const compositeKey = target.join("_");
        if (fieldMap[compositeKey]) {
            return `${fieldMap[compositeKey]} already exists`;
        }
        
        const friendlyFields = target
            .map((field: string) => fieldMap[field] || field)
            .join(" and ");
        
        return `${friendlyFields} combination already exists`;
    }
    
    // Handle single field unique constraints
    const field = Array.isArray(target) && target.length > 0 
        ? target[0] 
        : String(target);
    
    const friendly = fieldMap[field] || field;
    return `${friendly} already exists or is taken`;
}

/**
 * Sanitizes errors for client responses - logs technical details server-side,
 * returns user-friendly messages to clients
 * 
 * @param error - The error object
 * @param context - Context where error occurred (e.g., "login", "signup", "profile update")
 * @returns Object with user-friendly message and status code
 */
export function sanitizeErrorForClient(
    error: unknown,
    context: string = "request"
): { message: string; statusCode: number } {
    // Log full error details server-side for debugging
    console.error(`[${context}] Error details:`, {
        error,
        message: error instanceof Error ? error.message : String(error),
        stack: error instanceof Error ? error.stack : undefined,
        name: error instanceof Error ? error.name : undefined,
    });

    // Handle Prisma errors
    if (error && typeof error === "object" && "code" in error) {
        const prismaError = error as { code?: string; message?: string };
        
        // Database connection errors
        if (prismaError.code === "P1001" || prismaError.message?.includes("Can't reach database")) {
            return {
                message: "Database connection failed. Please try again later.",
                statusCode: 503,
            };
        }
        
        // Query timeout
        if (prismaError.code === "P1008") {
            return {
                message: "Request timed out. Please try again.",
                statusCode: 504,
            };
        }
        
        // Record not found (P2025) - can be user-friendly in some contexts
        if (prismaError.code === "P2025") {
            return {
                message: "The requested resource was not found.",
                statusCode: 404,
            };
        }
        
        // Other Prisma errors - generic message
        if (prismaError.code?.startsWith("P")) {
            return {
                message: "A database error occurred. Please try again later.",
                statusCode: 500,
            };
        }
    }

    // Handle known error types
    if (error instanceof Error) {
        // OAuth/Google errors
        if (error.message.includes("SHA-1") || 
            error.message.includes("ApiException") ||
            error.message.includes("OAuth") ||
            error.message.includes("signingReport")) {
            return {
                message: "Google Sign-In is not properly configured. Please contact support.",
                statusCode: 503,
            };
        }

        // Network/connection errors
        if (error.message.includes("ECONNREFUSED") ||
            error.message.includes("ENOTFOUND") ||
            error.message.includes("timeout")) {
            return {
                message: "Unable to connect to the server. Please check your internet connection.",
                statusCode: 503,
            };
        }

        // Validation errors (Zod) - these are usually safe to show
        if (error.name === "ZodError") {
            return {
                message: error.message || "Validation error",
                statusCode: 400,
            };
        }
    }

    // Default: generic error message (never expose technical details)
    return {
        message: "An unexpected error occurred. Please try again later.",
        statusCode: 500,
    };
}
