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
