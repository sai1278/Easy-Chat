package media

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"time"
)

// StorageClient orchestrates secure, transient media url signing.
type StorageClient struct {
	secretKey  string
	bucketName string
}

func NewStorageClient(secretKey, bucketName string) *StorageClient {
	return &StorageClient{
		secretKey:  secretKey,
		bucketName: bucketName,
	}
}

// GenerateUploadURL generates a cryptographically signed URL with a hardcoded 10-minute expiry (TTL).
func (s *StorageClient) GenerateUploadURL(objectKey string) (string, time.Time) {
	// Enforce 10-minute TTL requirement (Decision 1)
	expiry := time.Now().Add(10 * time.Minute)
	expiryUnix := expiry.Unix()
	
	mac := hmac.New(sha256.New, []byte(s.secretKey))
	msg := fmt.Sprintf("%s:%s:%d", s.bucketName, objectKey, expiryUnix)
	mac.Write([]byte(msg))
	signature := hex.EncodeToString(mac.Sum(nil))
	
	url := fmt.Sprintf("https://media.nearbyconnect.com/%s/%s?expires=%d&sig=%s",
		s.bucketName, objectKey, expiryUnix, signature)
		
	return url, expiry
}

// VerifySignature asserts the validity of the signed URL.
func (s *StorageClient) VerifySignature(objectKey string, expiryUnix int64, signature string) bool {
	// Immediate check for expiration time
	if time.Now().Unix() > expiryUnix {
		return false
	}
	
	mac := hmac.New(sha256.New, []byte(s.secretKey))
	msg := fmt.Sprintf("%s:%s:%d", s.bucketName, objectKey, expiryUnix)
	mac.Write([]byte(msg))
	expectedSig := hex.EncodeToString(mac.Sum(nil))
	
	return hmac.Equal([]byte(signature), []byte(expectedSig))
}
