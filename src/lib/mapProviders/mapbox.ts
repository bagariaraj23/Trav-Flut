import { ENV } from "@/env";
import { NormalizedPlace, PlacesProviderAdapter } from "./adapter";

// Mapping Mapbox feature types to our place types
function mapFeatureType(featureType: string | undefined): string {
  if (!featureType) return 'POI';

  const type = featureType.toLowerCase();

  // City-level places
  if (type.includes('place') ||
    type.includes('city') ||
    type.includes('region') ||
    type.includes('country') ||
    type.includes('locality.place')) {
    return 'CITY';
  }

  // District-level places
  if (type.includes('district') ||
    type.includes('neighborhood') ||
    type.includes('locality') ||
    type.includes('postcode') ||
    type.includes('suburb') ||
    type.includes('borough')) {
    return 'DISTRICT';
  }

  // Everything else is considered a POI
  return 'POI';
}

export class MapboxPlacesAdapter implements PlacesProviderAdapter {
  async search({
    q,
    lat,
    lng,
    limit = 10,
  }: {
    q: string;
    lat?: number;
    lng?: number;
    radius?: number;
    placeType?: string;
    limit?: number;
  }): Promise<NormalizedPlace[]> {
    const proximity =
      lat != null && lng != null ? `&proximity=${lng},${lat}` : "";
    const url = `https://api.mapbox.com/search/geocode/v6/forward?q=${encodeURIComponent(
      q
    )}${proximity}&limit=${limit}&access_token=${ENV.MAPBOX_ACCESS_TOKEN}`;
    const res = await fetch(url, { cache: "no-store" as any });
    if (!res.ok) return [];
    const data = await res.json();
    const features: any[] = data?.features ?? [];
    return features
      .map((f) => {
        const coords = f?.geometry?.coordinates;
        const props = f?.properties ?? {};
        return {
          name: props?.name ?? f?.text ?? f?.place_name ?? "Unknown",
          address: f?.place_name ?? props?.full_address ?? undefined,
          lat: Array.isArray(coords) ? coords[1] : undefined,
          lng: Array.isArray(coords) ? coords[0] : undefined,
          externalId: f?.id,
          placeType: mapFeatureType(props?.feature_type ?? props?.category),
          source: "MAPBOX" as const,
        } as NormalizedPlace;
      })
      .filter((p) => typeof p.lat === "number" && typeof p.lng === "number");
  }
}
