import { ENV } from "@/env";
import { NormalizedPlace, PlacesProviderAdapter } from "./adapter";

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
          placeType: props?.feature_type ?? props?.category ?? undefined,
          source: "MAPBOX" as const,
        } as NormalizedPlace;
      })
      .filter((p) => typeof p.lat === "number" && typeof p.lng === "number");
  }
}
