import { TripResponse, UserProfile } from '../types/api';

export const mockUser: UserProfile = {
  id: '1',
  email: 'sarah@example.com',
  username: 'sarahexplores',
  name: 'Sarah Chen',
  avatarUrl: 'https://images.pexels.com/photos/1239291/pexels-photo-1239291.jpeg?auto=compress&cs=tinysrgb&w=150&h=150&dpr=2',
  bio: 'Digital nomad • Travel photographer • Food enthusiast',
  isPrivate: false,
  createdAt: new Date().toISOString(),
  updatedAt: new Date().toISOString()
};

export const mockTrips: TripResponse[] = [
  {
    id: "1",
    userId: "1",
    title: "Tokyo Adventure",
    destinations: ["Tokyo, Japan"],
    startDate: new Date("2024-01-15").toISOString(),
    endDate: new Date("2024-01-22").toISOString(),
    status: "ENDED",
    mood: "CULTURAL",
    type: "SOLO",
    coverMediaUrl:
      "https://images.pexels.com/photos/2506923/pexels-photo-2506923.jpeg?auto=compress&cs=tinysrgb&w=600",
    description:
      "Exploring the vibrant culture, incredible food, and modern marvels of Tokyo",
    createdAt: new Date("2024-01-10").toISOString(),
    updatedAt: new Date("2024-01-22").toISOString(),
    entryCount: 15,
    participantCount: 23,
    threadEntries: [
      {
        id: "1",
        tripId: "1",
        authorId: "1",
        type: "TEXT",
        contentText:
          "Just arrived in Tokyo! The energy here is incredible. First stop: Shibuya Crossing to experience the famous organized chaos. The jetlag is real but the excitement is keeping me going! 🇯🇵",
        locationName: "Shibuya Crossing",
        gpsCoordinates: { lat: 35.6591, lng: 139.7005 },
        createdAt: new Date("2024-01-15T10:30:00").toISOString(),
        author: mockUser,
      },
      {
        id: "2",
        tripId: "1",
        authorId: "1",
        type: "MEDIA",
        contentText:
          "Lunch at this hidden ramen shop recommended by a local. The broth is absolutely divine!",
        mediaUrl:
          "https://images.pexels.com/photos/1907228/pexels-photo-1907228.jpeg?auto=compress&cs=tinysrgb&w=600",
        locationName: "Menya Saimi",
        gpsCoordinates: { lat: 35.658, lng: 139.7016 },
        createdAt: new Date("2024-01-15T14:20:00").toISOString(),
        author: mockUser,
        media: {
          id: "1",
          url: "https://images.pexels.com/photos/1907228/pexels-photo-1907228.jpeg?auto=compress&cs=tinysrgb&w=600",
          type: "IMAGE",
          filename: "ramen.jpg",
          size: 524288,
          uploadedById: "1",
          tripId: "1",
          createdAt: new Date("2024-01-15T14:20:00").toISOString(),
        },
      },
      {
        id: "3",
        tripId: "1",
        authorId: "1",
        type: "CHECKIN",
        contentText:
          "Peaceful morning at Senso-ji Temple. The contrast between ancient traditions and modern Tokyo is fascinating.",
        locationName: "Senso-ji Temple",
        gpsCoordinates: { lat: 35.7148, lng: 139.7967 },
        createdAt: new Date("2024-01-16T09:15:00").toISOString(),
        author: mockUser,
      },
    ],
    _count: {
      threadEntries: 3,
      media: 1,
      participants: 1,
    },
  },
  {
    id: "2",
    userId: "1",
    title: "Bali Escape",
    destinations: ["Bali, Indonesia"],
    startDate: new Date("2024-02-10").toISOString(),
    endDate: new Date("2024-02-17").toISOString(),
    status: "ENDED",
    mood: "RELAXED",
    type: "SOLO",
    coverMediaUrl:
      "https://images.pexels.com/photos/3073666/pexels-photo-3073666.jpeg?auto=compress&cs=tinysrgb&w=600",
    description: "Island paradise, temples, and incredible sunsets",
    createdAt: new Date("2024-02-05").toISOString(),
    updatedAt: new Date("2024-02-17").toISOString(),
    entryCount: 15,
    participantCount: 23,
    threadEntries: [
      {
        id: "4",
        tripId: "2",
        authorId: "1",
        type: "MEDIA",
        contentText:
          "Sunset at Tanah Lot Temple. No words can describe this beauty.",
        mediaUrl:
          "https://images.pexels.com/photos/2161449/pexels-photo-2161449.jpeg?auto=compress&cs=tinysrgb&w=600",
        locationName: "Tanah Lot Temple",
        gpsCoordinates: { lat: -8.6211, lng: 115.0864 },
        createdAt: new Date("2024-02-10T16:45:00").toISOString(),
        author: mockUser,
        media: {
          id: "2",
          url: "https://images.pexels.com/photos/2161449/pexels-photo-2161449.jpeg?auto=compress&cs=tinysrgb&w=600",
          type: "IMAGE",
          filename: "tanah_lot_sunset.jpg",
          size: 1048576,
          uploadedById: "1",
          tripId: "2",
          createdAt: new Date("2024-02-10T16:45:00").toISOString(),
        },
      },
    ],
    _count: {
      threadEntries: 1,
      media: 1,
      participants: 1,
    },
  },
  {
    id: "3",
    userId: "1",
    title: "Iceland Road Trip",
    destinations: ["Reykjavik, Iceland"],
    startDate: new Date("2024-03-01").toISOString(),
    status: "UPCOMING",
    mood: "ADVENTURE",
    type: "SOLO",
    coverMediaUrl:
      "https://images.pexels.com/photos/1586298/pexels-photo-1586298.jpeg?auto=compress&cs=tinysrgb&w=600",
    description: "Chasing waterfalls and northern lights on the Ring Road",
    createdAt: new Date("2024-02-20").toISOString(),
    updatedAt: new Date("2024-02-20").toISOString(),
    entryCount: 15,
    participantCount: 23,
    threadEntries: [],
    _count: {
      threadEntries: 0,
      media: 0,
      participants: 1,
    },
  },
];