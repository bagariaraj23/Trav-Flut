export function handlePrismaUniqueError(
    error: any,
    fieldMap: Record<string, string> = {}
): string | null {
    if (!error || error.code !== "P2002") return null;
    const target = error.meta?.target ?? [];
    const field = Array.isArray(target) && target.length > 0 ? target[0] : String(target);
    const friendly = fieldMap[field] || field;
    return `${friendly} already exists`;
}
