export interface ApiResponse<T = any> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
}

export interface AuthResponse {
  user: UserProfile;
  accessToken: string;
  refreshToken: string;
}

export interface UserProfile {
  id: string;
  email: string;
  username?: string;
  name?: string;
  avatarUrl?: string;
  bio?: string;
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
  username?: string;
  name?: string;
  avatarUrl?: string;
  bio?: string;
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
  description?: string;
  startDate?: string;
  endDate?: string;
  destinations: string[];
  mood?: "RELAXED" | "ADVENTURE" | "SPIRITUAL" | "CULTURAL" | "PARTY" | "MIXED";
  type?: "SOLO" | "GROUP" | "COUPLE" | "FAMILY";
  coverMediaUrl?: string;
  status: "UPCOMING" | "ONGOING" | "ENDED";
  createdAt: string;
  updatedAt: string;
  user?: UserProfile;
  participants?: TripParticipantResponse[];
  threadEntries?: TripThreadEntryResponse[];
  finalPost?: TripFinalPostResponse;
  _count?: {
    threadEntries: number;
    media: number;
    participants: number;
  };
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
  contentText?: string;
  mediaUrl?: string;
  locationName?: string;
  gpsCoordinates?: { lat: number; lng: number };
  createdAt: string;
  author: UserProfile;
  taggedUsers?: UserProfile[];
  media?: MediaResponse;
}

export interface TripFinalPostResponse {
  id: string;
  tripId: string;
  summaryText: string;
  curatedMedia: string[];
  caption?: string;
  isPublished: boolean;
  createdAt: string;
}

export interface MediaResponse {
  id: string;
  url: string;
  type: "IMAGE" | "VIDEO";
  filename?: string;
  size?: number;
  uploadedById: string;
  tripId?: string;
  createdAt: string;
}

// Request DTOs
export interface CreateTripRequest {
  title: string;
  description?: string;
  startDate?: string;
  endDate?: string;
  destinations: string[];
  mood?: "RELAXED" | "ADVENTURE" | "SPIRITUAL" | "CULTURAL" | "PARTY" | "MIXED";
  type?: "SOLO" | "GROUP" | "COUPLE" | "FAMILY";
  coverMediaUrl?: string;
}

export interface CreateThreadEntryRequest {
  type: "TEXT" | "MEDIA" | "LOCATION" | "CHECKIN";
  contentText?: string;
  mediaUrl?: string;
  locationName?: string;
  gpsCoordinates?: { lat: number; lng: number };
  taggedUserIds?: string[];
}

export interface AddParticipantRequest {
  userId: string;
  role?: string;
}

export interface UpdateFinalPostRequest {
  summaryText: string;
  curatedMedia: string[];
  caption?: string;
}
