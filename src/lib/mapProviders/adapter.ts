export type NormalizedPlace = {
  name: string;
  address?: string;
  lat: number;
  lng: number;
  externalId?: string;
  placeType?: string;
  source: "MAPBOX" | "GOOGLE" | "MAPLIBRE" | "APPLE" | "USER";
};

export interface PlacesProviderAdapter {
  search(params: {
    q: string;
    lat?: number;
    lng?: number;
    radius?: number;
    placeType?: string;
    limit?: number;
  }): Promise<NormalizedPlace[]>;
}

function mapPlaceType(mapboxType: string): string {
  const typeMap: Record<string, string> = {
    poi: "POI",
    address: "POI",
    place: "OTHER",
    region: "OTHER",
    district: "OTHER",
    locality: "OTHER",
    neighborhood: "OTHER",
    postcode: "OTHER",
  };

  return typeMap[mapboxType.toLowerCase()] || "OTHER";
}