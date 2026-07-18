# Walkthrough - Media Service

I have successfully implemented the Media Service. Below is the summary of the architectural components, verification testing, and results.

## Changes Made

### 1. Workspace Configuration
- [go.work](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/Easy%20Chat/go.work): Registered the new `./apps/backend/services/media` service module.
- [go.mod](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/Easy%20Chat/apps/backend/services/media/go.mod): Created a module definition importing local backend shared libraries and installing S3-compatible cloud storage SDK components.

### 2. Domain Entities & Interfaces
- [media.go](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/Easy%20Chat/apps/backend/services/media/internal/domain/media.go): Defined the core models `FileMetadata` (containing UUID, size, contentType, S3Key parameters) and `PreSignedUrlResponse`.
- [repository.go](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/Easy%20Chat/apps/backend/services/media/internal/domain/repository.go): Defined interfaces `MetadataRepository` (Postgres records), `StorageRepository` (S3 client functions), and `ScannerPipeline` (malware streams scanning).

### 3. Application Use Cases
- [media_usecase.go](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/Easy%20Chat/apps/backend/services/media/internal/application/media_usecase.go): Implemented core workflows:
  - Enforcing file size limit thresholds (10MB).
  - Scanning file payloads using the virus scanning pipeline.
  - Image optimization: Decodes and compresses JPEG and PNG uploads to JPEG format (75% quality) to minimize network overhead and storage footprints.
  - S3 cloud uploads and PostgreSQL metadata persistence.
  - Generating pre-signed S3 upload and download endpoints.

### 4. Repository Adapters
- [postgres.go](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/Easy%20Chat/apps/backend/services/media/internal/infrastructure/persistence/postgres.go): Configured PostgreSQL metadata persistence.
- [s3_storage.go](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/Easy%20Chat/apps/backend/services/media/internal/infrastructure/storage/s3_storage.go): Integrated standard AWS SDK for Go S3 client. Implements bucket uploads, pre-signed URL presigning, CDN domain mappings, and a zero-configuration local cache fallback.
- [scanner.go](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/Easy%20Chat/apps/backend/services/media/internal/infrastructure/scanner/scanner.go): Anti-virus pipeline implementing TCP stream commands (INSTREAM) to ClamAV daemons, and falling back to EICAR antivirus test signature checking.

### 5. Transport Layer and Entry Point
- [handler.go](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/Easy%20Chat/apps/backend/services/media/internal/transport/http/handler.go): Exposes REST HTTP controllers for file uploads, signed upload URLs, and download redirects. Offloads streaming bandwidth from application servers to pre-signed cloud/CDN URLs.
- [main.go](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/Easy%20Chat/apps/backend/services/media/cmd/media/main.go): Wired the main server bootstrap routine and started the HTTP server.

---

## Verification Results

### Automated Integration Tests
Written integration unit tests under [media_usecase_test.go](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/Easy%20Chat/apps/backend/services/media/internal/application/media_usecase_test.go) asserting:
1. **Size limits**: Requests containing file size payloads over 10MB are blocked and return `ErrFileTooLarge`.
2. **Malware detection**: Payloads containing virus signatures (e.g. EICAR test string) are successfully captured and blocked (`ErrVirusDetected`).
3. **Image compression**: PNG test images are successfully decoded, compressed, and written to storage in JPEG format (75% quality).
4. **Pre-signed S3 URLs**: Verifies that pre-signed upload and download endpoints parse correctly.

All tests compiled and passed successfully:
```
=== RUN   TestMediaUsecase_ProcessUpload_SizeLimit
--- PASS: TestMediaUsecase_ProcessUpload_SizeLimit (0.02s)
=== RUN   TestMediaUsecase_ProcessUpload_MalwareDetection
--- PASS: TestMediaUsecase_ProcessUpload_MalwareDetection (0.00s)
=== RUN   TestMediaUsecase_ProcessUpload_ImageCompression
--- PASS: TestMediaUsecase_ProcessUpload_ImageCompression (0.03s)
=== RUN   TestMediaUsecase_PreSignedURLs
--- PASS: TestMediaUsecase_PreSignedURLs (0.00s)
PASS
ok  	nearby/backend/services/media/internal/application	1.097s
```
