# MockData Usage Guide for Cloudinary Media

## Important Notes

The `mockData.ts` file currently uses hardcoded media IDs (e.g., `"1"`, `"2"`) which won't work with actual Cloudinary images in production.

## For Testing with Cloudinary Images

To test with actual Cloudinary images, you need to:

### Option 1: Create Media Records First (Recommended)

1. **Upload images to Cloudinary** using your app's media upload flow
2. **Note the Media IDs** returned from the upload confirmation endpoint
3. **Update mockData.ts** to use these actual Media IDs:

```typescript
{
  id: "2",
  tripId: "1",
  authorId: "1",
  type: "MEDIA",
  contentText: "Lunch at this hidden ramen shop...",
  mediaId: "actual-media-id-from-database", // Replace with real Media ID
  media: {
    id: "actual-media-id-from-database",
    url: "https://res.cloudinary.com/your-cloud/image/upload/v1234567890/your-image.jpg",
    publicId: "tripthread/user-id/trip-id/thread_entry/timestamp_filename",
    type: "IMAGE",
    filename: "ramen.jpg",
    size: 524288,
    uploadedById: "1",
    tripId: "1",
    createdAt: new Date("2024-01-15T14:20:00").toISOString(),
  },
}
```

### Option 2: Use Test Media IDs from Your Database

If you've already uploaded test images, you can:

1. **Query your database** for existing Media records:
   ```sql
   SELECT id, url, publicId FROM media WHERE uploadedById = 'your-user-id' LIMIT 10;
   ```

2. **Update mockData.ts** with these real IDs and URLs

### Option 3: Create Media Records via Script

You can create Media records in your seed script:

```typescript
// In seed.ts or a test script
const mediaRecord = await prisma.media.create({
  data: {
    url: "https://res.cloudinary.com/your-cloud/image/upload/v1234567890/image.jpg",
    publicId: "tripthread/user-id/trip-id/thread_entry/test_image",
    type: "IMAGE",
    filename: "test.jpg",
    size: 524288,
    uploadedById: userId,
    tripId: tripId,
    processingStatus: "COMPLETED",
  },
});

// Then use mediaRecord.id in mockData
```

## Current MockData Structure

The mockData currently includes:
- `mediaId`: String reference to Media model
- `media`: Full Media object with all details (for display purposes)

When the `mediaId` is set to `null` or an invalid ID, the app will:
- Not display media previews in thread entries
- Not break, but media-related features won't work

## For Production/Development

Always ensure:
1. `mediaId` references an actual Media record in your database
2. The Media record has a valid `url` pointing to Cloudinary
3. The `publicId` matches the Cloudinary resource path

