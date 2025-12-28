/**
 * Base62 encoding for more compact keys while remaining URL-safe
 * Using a modified base62 that's case-sensitive for more density
 */
const base62Chars = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";

function toBase62(num: number): string {
    if (num === 0) return "0";
    let result = "";
    while (num > 0) {
        result = base62Chars[num % 62] + result;
        num = Math.floor(num / 62);
    }
    return result;
}

/**
 * Rounds and encodes a coordinate for cache key generation
 * Uses 4 decimals (11.1m precision) instead of 5 (1.1m precision)
 * Encodes as base62 for shorter strings
 */
export function bucketCoord(value: number): string {
    // Use 4 decimals (11.1m precision) instead of 5
    const factor = 10000;
    const encoded = toBase62(Math.round(value * factor));
    return encoded;
}

/**
 * Cache key generators for different types of place queries
 * Optimized for storage reduction:
 * - Shorter prefixes (p=place, s=search, n=nearby)
 * - Base62 encoded coordinates
 * - Minimal separators
 * - Optional params omitted entirely instead of empty strings
 */
export const cacheKeys = {
    /**
     * Primary place storage key
     * Format: p:{id} - Stores full place data
     */
    place: (id: string): string => `p:${id}`,

    /**
     * Place reference by external ID
     * Format: p:e:{externalId} - Stores only place ID reference
     */
    placeByExternal: (externalId: string): string => `p:e:${externalId}`,

    /**
     * Place reference by spatial key
     * Format: p:s:{spatialKey} - Stores only place ID reference
     */
    placeBySpatial: (spatialKey: string): string => `p:s:${spatialKey}`,

    /**
     * Place reference by name and spatial key
     * Format: p:n:{nameLower}:{spatialKey} - Stores only place ID reference
     */
    placeByName: (name: string, spatialKey: string): string =>
        `p:n:${name.toLowerCase()}:${spatialKey}`,

    /**
     * Generate a compact cache key for place search queries
     * Format: p:q:{query}{lat}{lng}{type}{limit}
     */
    search: (
        q: string,
        lat?: number,
        lng?: number,
        type?: string,
        limit?: number
    ): string => {
        // Start with minimal prefix
        let key = 'p:q:' + q;

        // Only add coordinates if both are present
        if (lat != null && lng != null) {
            key += ',' + bucketCoord(lat) + bucketCoord(lng);
        }

        // Only add type and limit if specified
        if (type) key += ',' + type;
        if (limit) key += ',' + limit;

        return key;
    },

    /**
     * Generate a compact cache key for nearby place queries
     * Format: p:n:{lat}{lng}{kinds}
     */
    nearby: (lat: number, lng: number, kinds?: string): string => {
        let key = 'p:n:' + bucketCoord(lat) + bucketCoord(lng);
        if (kinds) key += ',' + kinds;
        return key;
    }
};
