# Cloudinary Media Upload Implementation

This implementation adds Cloudinary media upload functionality to Trav-Flut, based on the TripThread implementation.

## Features Implemented

### Backend Changes
1. **Updated Prisma Schema** (`prisma/schema.prisma`):
   - Added `publicId` field to `Media` model for Cloudinary management
   - Added `coverMediaId` field to `Trip` model with relation to `Media`
   - Added `mediaId` field to `TripThreadEntry` model with relation to `Media`
   - Maintained backward compatibility with existing `coverMediaUrl` and `mediaUrl` fields

2. **Cloudinary Service** (`src/lib/cloudinary.ts`):
   - Server-side signature generation for secure uploads
   - Media upload confirmation and database record creation
   - File validation and security checks

3. **API Endpoints**:
   - `POST /api/media/cloudinary-signature` - Get signed upload parameters
   - `POST /api/media/confirm` - Confirm upload and create Media record

4. **Updated Validation** (`src/lib/validation.ts`):
   - Added support for `coverMediaId` and `mediaId` fields
   - Updated validation logic for media entries

### Frontend Changes
1. **Updated Models** (`mobile/lib/models/trip.dart`):
   - Added `publicId` field to `Media` model
   - Added `coverMediaId` and `coverMedia` fields to `Trip` model
   - Added `mediaId` field to `TripThreadEntry` model
   - Updated request DTOs to support new fields

2. **Enhanced API Service** (`mobile/lib/services/api_service.dart`):
   - Added `getCloudinarySignature()` method
   - Added `confirmMediaUpload()` method
   - Updated `createTrip()` to support `coverMediaId`

3. **Updated MediaService** (`mobile/lib/services/media_service.dart`):
   - Added `uploadMediaToCloudinary()` method for complete upload flow
   - Integrated with ApiService for backend communication
   - Added direct Cloudinary upload functionality

4. **Service Injection** (`mobile/lib/main.dart`):
   - Updated MediaService to receive ApiService dependency

## Setup Instructions

### 1. Environment Variables
Add these environment variables to your `.env.local` file:

```env
# Cloudinary Configuration
CLOUDINARY_CLOUD_NAME="your_cloudinary_cloud_name"
CLOUDINARY_API_KEY="your_cloudinary_api_key"
CLOUDINARY_API_SECRET="your_cloudinary_api_secret"
CLOUDINARY_UPLOAD_FOLDER="trav-flut_uploads"
```

### 2. Database Migration
Run the Prisma migration to update the database schema:

```bash
npx prisma migrate dev --name add_cloudinary_media_support
```

### 3. Generate Prisma Client
```bash
npx prisma generate
```

### 4. Flutter Dependencies
Ensure these dependencies are in your `pubspec.yaml`:

```yaml
dependencies:
  dio: ^5.0.0
  image_picker: ^1.0.0
```

### 5. Regenerate Flutter Models
```bash
cd mobile
dart run build_runner build --delete-conflicting-outputs
```

## Usage

### Upload Media for Trip Cover
```dart
// In CreateTripScreen
final file = await mediaService.pickImage(fromCamera: false);
if (file != null) {
  final media = await mediaService.uploadMediaToCloudinary(file, tripId);
  if (media != null) {
    // Use media.id as coverMediaId when creating trip
    final trip = await apiService.createTrip(
      title: title,
      destinations: destinations,
      coverMediaId: media.id, // Use the new field
    );
  }
}
```

### Upload Media for Thread Entry
```dart
// In TripThreadScreen
final file = await mediaService.pickImage(fromCamera: false);
if (file != null) {
  final media = await mediaService.uploadMediaToCloudinary(
    file, 
    tripId,
    threadEntryId: 'temp', // Will be updated after entry creation
  );
  if (media != null) {
    // Create thread entry with mediaId
    await apiService.createThreadEntry(
      tripId,
      CreateThreadEntryRequest(
        type: ThreadEntryType.media,
        mediaId: media.id, // Use the new field
        contentText: caption,
      ),
    );
  }
}
```

## Security Features

1. **Server-Signed Uploads**: All uploads are signed server-side to prevent unauthorized uploads
2. **File Validation**: Both client and server-side validation of file types and sizes
3. **Access Control**: Users can only upload to trips they own or participate in
4. **Unique Public IDs**: Each upload gets a unique Cloudinary public_id for management

## Migration Strategy

The implementation maintains backward compatibility:
- Existing `coverMediaUrl` and `mediaUrl` fields are preserved
- New uploads use `coverMediaId` and `mediaId` fields
- Both old and new fields can coexist during transition period

## Testing

The implementation includes mock mode support for testing without Cloudinary credentials:
- When Cloudinary credentials are not configured, mock responses are returned
- Placeholder images are used for testing upload flow
- All validation and error handling is preserved

## Next Steps

1. Update UI screens to use the new media upload functionality
2. Add progress indicators for upload operations
3. Implement media deletion functionality
4. Add image compression and optimization
5. Implement batch upload for multiple media files
