export interface ApiResponse<T = any> {
  success: boolean;
  data?: T | null;
  error?: string | null;
  message?: string | null;
}

export interface AuthResponse {
  user: UserProfile;
  accessToken: string;
  refreshToken: string;
}

export interface UserProfile {
  id: string;
  email: string;
  username?: string | null;
  name?: string | null;
  avatarUrl?: string | null;
  bio?: string | null;
  isPrivate: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface UserStats {
  tripCount: number;
  followerCount: number;
  followingCount: number;
}

export interface FollowResponse {
  id: string;
  followerId: string;
  followeeId: string;
  createdAt: string;
}

export interface FollowRequestResponse {
  id: string;
  senderId: string;
  receiverId: string;
  status: "PENDING" | "ACCEPTED" | "REJECTED";
  createdAt: string;
  updatedAt: string;
  sender?: UserProfile;
  receiver?: UserProfile;
}

export interface DiscoverUserDto {
  id: string;
  username?: string | null;
  name?: string | null;
  avatarUrl?: string | null;
  bio?: string | null;
  isPrivate: boolean;
  isFollowing: boolean;
  isFollowedBy: boolean;
  followRequestStatus?: "PENDING" | "ACCEPTED" | "REJECTED" | null; // null means no request sent
  hasRequestedToFollow?: boolean; // true if current user sent a request
  hasPendingRequestFrom?: boolean; // true if this user sent a request to current user
}

export interface PaginatedResponse<T> {
  items: T[];
  page: number;
  limit: number;
  total: number;
  hasNext: boolean;
}

// Trip Types
export interface TripResponse {
  id: string;
  userId: string;
  title: string;
  description?: string | null;
  startDate?: string | null;
  endDate?: string | null;
  destinations: string[];
  mood?: "RELAXED" | "ADVENTURE" | "SPIRITUAL" | "CULTURAL" | "PARTY" | "MIXED" | null;
  type?: "SOLO" | "GROUP" | "COUPLE" | "FAMILY" | null;
  coverMediaUrl?: string | null;
  status: "UPCOMING" | "ONGOING" | "ENDED";
  createdAt: string;
  updatedAt: string;
  user?: UserProfile | null;
  participants?: TripParticipantResponse[] | null;
  threadEntries?: TripThreadEntryResponse[] | null;
  finalPost?: TripFinalPostResponse | null;
  _count?: {
    threadEntries: number | null;
    media: number | null;
    participants: number | null;
  } | null;
}

export interface TripParticipantResponse {
  id: string;
  tripId: string;
  userId: string;
  role: string;
  joinedAt: string;
  user: UserProfile;
}

export interface TripThreadEntryResponse {
  id: string;
  tripId: string;
  authorId: string;
  type: "TEXT" | "MEDIA" | "LOCATION" | "CHECKIN";
  contentText?: string | null;
  mediaUrl?: string | null;
  locationName?: string | null;
  gpsCoordinates?: { lat: number | null; lng: number | null } | null;
  createdAt: string;
  author: UserProfile;
  taggedUsers?: UserProfile[] | null;
  media?: MediaResponse | null;
}

export interface TripFinalPostResponse {
  id: string;
  tripId: string;
  summaryText: string;
  curatedMedia: string[];
  caption?: string | null;
  isPublished: boolean;
  createdAt: string;
}

export interface MediaResponse {
  id: string;
  url: string;
  type: "IMAGE" | "VIDEO";
  filename?: string | null;
  size?: number | null;
  uploadedById: string;
  tripId?: string | null;
  createdAt: string;
}

// Request DTOs
export interface CreateTripRequest {
  title: string;
  description?: string | null;
  startDate?: string | null;
  endDate?: string | null;
  destinations: string[];
  mood?: "RELAXED" | "ADVENTURE" | "SPIRITUAL" | "CULTURAL" | "PARTY" | "MIXED" | null;
  type?: "SOLO" | "GROUP" | "COUPLE" | "FAMILY" | null;
  coverMediaUrl?: string | null;
}

export interface CreateThreadEntryRequest {
  type: "TEXT" | "MEDIA" | "LOCATION" | "CHECKIN";
  contentText?: string | null;
  mediaUrl?: string | null;
  locationName?: string | null;
  gpsCoordinates?: { lat: number | null; lng: number | null } | null;
  taggedUserIds?: string[] | null;
}

export interface AddParticipantRequest {
  userId: string | null;
  role?: string | null;
}

export interface UpdateFinalPostRequest {
  summaryText: string;
  curatedMedia: string[];
  caption?: string | null;
}
