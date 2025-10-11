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
