export interface ApiResponse<T = any> {
  success: boolean;
  data?: T | null;
  error?: string | null;
  message?: string | null;
  meta?: Record<string, any>;
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
  profileComplete?: boolean;
  /** True when the user has linked a Google account (for Settings UI). */
  hasGoogleLinked?: boolean;
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

export interface FollowStatusResponse {
  isFollowing: boolean;
  isFollowedBy: boolean;
  isRequestPending: boolean;
  isPrivate: boolean;
  requestId?: string;
  requestStatus?: "PENDING" | "ACCEPTED" | "REJECTED";
}

export interface FollowRequestDto {
  id: string;
  followerId: string;
  followeeId: string;
  status: "PENDING" | "ACCEPTED" | "REJECTED";
  createdAt: string;
  updatedAt: string;
  follower: UserProfile;
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
}

export interface PaginatedResponse<T> {
  items: T[];
  page: number;
  limit: number;
  total: number;
  hasNext: boolean;
}

/** Home "Happening Now" story ring: one circle per live traveller. */
export interface LiveTripStoryResponse {
  isSelf: boolean;
  user: UserProfile;
  trip: TripResponse;
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
  mood?:
    | "RELAXED"
    | "ADVENTURE"
    | "SPIRITUAL"
    | "CULTURAL"
    | "PARTY"
    | "MIXED"
    | null;
  type?: "SOLO" | "GROUP" | "COUPLE" | "FAMILY" | null;
  coverMediaId?: string | null;
  startLocationId?: string | null;
  endLocationId?: string | null;
  startLocation?: PlaceResponse | null;
  endLocation?: PlaceResponse | null;
  status: "UPCOMING" | "ONGOING" | "ENDED";
  createdAt: string;
  updatedAt: string;
  entryCount: number;
  participantCount: number;
  user?: UserProfile | null;
  participants?: TripParticipantResponse[] | null;
  threadEntries?: TripThreadEntryResponse[] | null;
  finalPost?: TripFinalPostResponse | null;
  coverMedia?: MediaResponse | null;
  /** Present on discover feed: whether the current user follows the trip owner. */
  isFollowing?: boolean;
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
  locationName?: string | null;
  gpsCoordinates?: { lat: number | null; lng: number | null } | null;
  placeId?: string | null;
  place?: PlaceResponse | null;
  createdAt: string;
  author: UserProfile;
  taggedUsers?: UserProfile[] | null;
  media?: MediaResponse | null;
}

/** Cursor-paginated GET /trips/:id/entries (newest page first; items ascending). */
export interface TripThreadEntriesPageResponse {
  items: (TripThreadEntryResponse & {
    likeCount: number;
    commentCount: number;
    hasLiked: boolean;
  })[];
  hasMoreOlder: boolean;
  nextOlderCursor: string | null;
}

export interface PlaceResponse {
  id: string;
  name: string;
  address?: string | null;
  lat: number;
  lng: number;
  placeType: "POI" | "STAY" | "FOOD" | "TRANSPORT" | "VIEWPOINT" | "OTHER";
  source: "USER" | "GOOGLE" | "MAPBOX" | "APPLE";
  externalId?: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface TripFinalPostResponse {
  id: string;
  tripId: string;
  summaryText: string;
  curatedMedia: string[];
  caption?: string | null;
  coverMediaUrl?: string | null;
  generationStatus: "DRAFT" | "GENERATING" | "READY" | "PUBLISHED" | "FAILED";
  isPublished: boolean;
  publishedAt?: string | null;
  createdAt: string;
  updatedAt: string;
  trip?: TripResponse | null;
  likeCount?: number;
  commentCount?: number;
  shareCount?: number;
  hasLiked?: boolean;
}

export interface MediaResponse {
  id: string;
  url: string;
  type: "IMAGE" | "VIDEO" | "AUDIO" | "GIF";
  filename?: string | null;
  size?: number | null;
  uploadedById: string;
  tripId?: string | null;
  createdAt: string;
  publicId?: string;
}

// Request DTOs
export interface CreateTripRequest {
  title: string;
  description?: string | null;
  startDate?: string | null;
  endDate?: string | null;
  destinations: string[];
  mood?:
  | "RELAXED"
  | "ADVENTURE"
  | "SPIRITUAL"
  | "CULTURAL"
  | "PARTY"
  | "MIXED"
  | null;
  type?: "SOLO" | "GROUP" | "COUPLE" | "FAMILY" | null;
  coverMediaId?: string | null;
}

export interface CreateThreadEntryRequest {
  type: "TEXT" | "MEDIA" | "LOCATION" | "CHECKIN";
  contentText?: string | null;
  mediaId?: string | null;
  locationName?: string | null;
  gpsCoordinates?: { lat: number | null; lng: number | null } | null;
  placeId?: string | null;
  taggedUsernames?: string[] | null;
  taggedUserIds?: string[] | null;
}

export interface AddParticipantRequest {
  userId: string | null;
  role?: string | null;
}

export interface UpdateFinalPostRequest {
  summaryText?: string;
  curatedMedia?: string[];
  caption?: string | null;
  coverMediaUrl?: string | null;
}

// Trip Join Request Types
export interface TripJoinRequestDto {
  id: string;
  tripId: string;
  senderId: string;
  receiverId: string;
  status: "PENDING" | "ACCEPTED" | "REJECTED";
  createdAt: string;
  updatedAt: string;
  trip?: {
    id: string;
    title: string;
    coverMediaUrl?: string;
    userId: string;
    destinations: string[];
    status: "UPCOMING" | "ONGOING" | "ENDED";
    startDate?: string;
    endDate?: string;
  };
  sender?: UserProfile;
  receiver?: UserProfile;
}

export type MapPlaceOrigin = "DESTINATION" | "THREAD_ENTRY" | "ON_TRIP";

export interface MapPlaceResponse {
  place: PlaceResponse;
  origin: MapPlaceOrigin;
  destinationIndex?: number;
  threadEntryId?: string;
  visitedAt?: string;
  dayIndex?: number;
  order?: number;
  placeOnTripId?: string;
  notes?: string | null;
  createdAt?: string;
}

export type ExpenseCategory =
  | "FOOD"
  | "STAY"
  | "TRANSPORT"
  | "ACTIVITIES"
  | "SHOPPING"
  | "OTHER";

export type ExpenseSplitMethod = "EQUAL" | "EXACT" | "PERCENT" | "SHARES";

export type TripSettlementStatus =
  | "PAID"
  | "PENDING"
  | "COMPLETED"
  | "FAILED"
  | "CANCELLED"
  | "DISPUTED";

export interface ExpenseUserSummary {
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

export interface TripExpenseShareResponse {
  userId: string;
  shareMinor: number;
  weight?: number | null;
  user: ExpenseUserSummary;
}

export interface TripExpenseResponse {
  id: string;
  tripId: string;
  createdById: string;
  payerId: string;
  title: string;
  category: ExpenseCategory;
  amountMinor: number;
  currency: string;
  splitMethod: ExpenseSplitMethod;
  note?: string | null;
  createdAt: string;
  createdBy: ExpenseUserSummary;
  payer: ExpenseUserSummary;
  shares: TripExpenseShareResponse[];
}

export interface TripExpenseListResponse {
  items: TripExpenseResponse[];
  page: number;
  limit: number;
  total: number;
  hasNext: boolean;
}

export interface ExpenseMemberBalance {
  userId: string;
  name?: string | null;
  username?: string | null;
  avatarUrl?: string | null;
  netMinor: number;
  paidMinor: number;
  owedMinor: number;
}

export interface OpenTransferResponse {
  fromUserId: string;
  toUserId: string;
  amountMinor: number;
  canMarkPaid: boolean;
}

export interface RecordedSettlementResponse {
  id: string;
  fromUserId: string;
  toUserId: string;
  amountMinor: number;
  status: TripSettlementStatus;
  createdAt: string;
  fromUser?: ExpenseUserSummary;
  toUser?: ExpenseUserSummary;
  canUndo?: boolean;
}

export interface PairwiseBalanceResponse {
  otherUserId: string;
  netMinor: number;
  sharedCount: number;
  youOweMinor: number;
  theyOweMinor: number;
}

export interface ExpenseSummaryResponse {
  currency: string;
  totalSpendMinor: number;
  myNetMinor: number;
  members: ExpenseMemberBalance[];
  openTransfers: OpenTransferResponse[];
  recordedSettlements: RecordedSettlementResponse[];
  pairwise: PairwiseBalanceResponse[];
}

export interface CreateExpenseRequest {
  title: string;
  category: ExpenseCategory;
  amountMinor: number;
  payerId: string;
  splitMethod: ExpenseSplitMethod;
  memberIds: string[];
  shares?: { userId: string; shareMinor: number }[];
  percentBps?: { userId: string; bps: number }[];
  weights?: { userId: string; weight: number }[];
  note?: string | null;
}

export interface CreateSettlementRequest {
  fromUserId: string;
  toUserId: string;
  amountMinor: number;
}
