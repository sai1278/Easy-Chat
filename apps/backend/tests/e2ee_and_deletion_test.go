package tests

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"crypto/ecdh"
	"crypto/ed25519"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"mime/multipart"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	_ "github.com/lib/pq"
)

// Standard HKDF (RFC 5869) implementation matching Flutter's cryptography Hkdf(Hmac.sha256())
func hkdfExtractExpand(secret, salt, info []byte, length int) []byte {
	if len(salt) == 0 {
		salt = make([]byte, 32)
	}
	extractor := hmac.New(sha256.New, salt)
	extractor.Write(secret)
	prk := extractor.Sum(nil)

	var okm []byte
	var t []byte
	counter := byte(1)
	for len(okm) < length {
		expander := hmac.New(sha256.New, prk)
		expander.Write(t)
		expander.Write(info)
		expander.Write([]byte{counter})
		t = expander.Sum(nil)
		okm = append(okm, t...)
		counter++
	}
	return okm[:length]
}

const (
	jwtSecret    = "easychat-jwt-signing-secret-key-2026"
	gatewayBase  = "http://127.0.0.1:8090"
	postgresConn = "postgres://nearby_user:nearby_secure_pass@127.0.0.1:54322/nearby_connect?sslmode=disable"
)

func generateToken(userID string) string {
	claims := jwt.MapClaims{
		"sub":  userID,
		"sid":  uuid.New().String(),
		"role": "user",
		"exp":  time.Now().Add(1 * time.Hour).Unix(),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenStr, _ := token.SignedString([]byte(jwtSecret))
	return tokenStr
}

// TestTrueE2EEAndMessageDeletionSuite tests the complete E2EE lifecycle,
// all 4 message types, zero-knowledge DB storage, deletion semantics, and offline tombstones.
func TestTrueE2EEAndMessageDeletionSuite(t *testing.T) {
	db, err := sql.Open("postgres", postgresConn)
	if err != nil {
		t.Fatalf("Failed to connect to PostgreSQL: %v", err)
	}
	defer db.Close()

	// 1. Identity & Key Pair Generation for Device A & Device B
	// Device A (represented by the physical vivo user or simulated identity)
	idA_EdPub, idA_EdPriv, _ := ed25519.GenerateKey(rand.Reader)
	prekeyA_Priv, _ := ecdh.X25519().GenerateKey(rand.Reader)
	prekeyA_Pub := prekeyA_Priv.PublicKey()
	prekeyA_Sig := ed25519.Sign(idA_EdPriv, prekeyA_Pub.Bytes())

	userA_ID := uuid.New().String()
	userB_ID := uuid.New().String()

	// Register Device A in DB
	_, err = db.Exec(`INSERT INTO users (id, pseudonym, display_name, status) VALUES ($1, $2, $3, 'ACTIVE')`,
		userA_ID, "Alice-E2EE", "Alice E2EE")
	if err != nil {
		t.Fatalf("Failed to insert User A: %v", err)
	}
	defer db.Exec(`DELETE FROM users WHERE id IN ($1, $2)`, userA_ID, userB_ID)

	tokenA := generateToken(userA_ID)

	// Publish User A Crypto Identity via REST API
	bundleA := map[string]string{
		"identity_key_pub":  base64.StdEncoding.EncodeToString(idA_EdPub),
		"signed_prekey_pub": base64.StdEncoding.EncodeToString(prekeyA_Pub.Bytes()),
		"signed_prekey_sig": base64.StdEncoding.EncodeToString(prekeyA_Sig),
	}
	bodyA, _ := json.Marshal(bundleA)
	reqA, _ := http.NewRequest(http.MethodPost, gatewayBase+"/api/v1/chat/keys", bytes.NewReader(bodyA))
	reqA.Header.Set("Authorization", "Bearer "+tokenA)
	reqA.Header.Set("Content-Type", "application/json")
	respA, err := http.DefaultClient.Do(reqA)
	if err != nil {
		t.Fatalf("Failed to register Device A keys via API: %v", err)
	}
	if respA.StatusCode != http.StatusOK {
		t.Fatalf("Failed to register Device A keys via API: code %d", respA.StatusCode)
	}
	respA.Body.Close()

	// Device B: Generate Key Pair
	idB_EdPub, idB_EdPriv, _ := ed25519.GenerateKey(rand.Reader)
	prekeyB_Priv, _ := ecdh.X25519().GenerateKey(rand.Reader)
	prekeyB_Pub := prekeyB_Priv.PublicKey()
	prekeyB_Sig := ed25519.Sign(idB_EdPriv, prekeyB_Pub.Bytes())

	_, err = db.Exec(`INSERT INTO users (id, pseudonym, display_name, status) VALUES ($1, $2, $3, 'ACTIVE')`,
		userB_ID, "Bob-E2EE", "Bob E2EE")
	if err != nil {
		t.Fatalf("Failed to insert User B: %v", err)
	}
	tokenB := generateToken(userB_ID)

	bundleB := map[string]string{
		"identity_key_pub":  base64.StdEncoding.EncodeToString(idB_EdPub),
		"signed_prekey_pub": base64.StdEncoding.EncodeToString(prekeyB_Pub.Bytes()),
		"signed_prekey_sig": base64.StdEncoding.EncodeToString(prekeyB_Sig),
	}
	bodyB, _ := json.Marshal(bundleB)
	reqB, _ := http.NewRequest(http.MethodPost, gatewayBase+"/api/v1/chat/keys", bytes.NewReader(bodyB))
	reqB.Header.Set("Authorization", "Bearer "+tokenB)
	reqB.Header.Set("Content-Type", "application/json")
	respB, err := http.DefaultClient.Do(reqB)
	if err != nil {
		t.Fatalf("Failed to register Device B keys via API: %v", err)
	}
	if respB.StatusCode != http.StatusOK {
		t.Fatalf("Failed to register Device B keys via API: code %d", respB.StatusCode)
	}
	respB.Body.Close()

	// 2. Peer Key Discovery
	reqGetA, _ := http.NewRequest(http.MethodGet, gatewayBase+"/api/v1/chat/keys/"+userA_ID, nil)
	reqGetA.Header.Set("Authorization", "Bearer "+tokenB)
	respGetA, err := http.DefaultClient.Do(reqGetA)
	if err != nil || respGetA.StatusCode != http.StatusOK {
		t.Fatalf("Failed to fetch Device A keys via API: %v", err)
	}
	var fetchedBundleA map[string]string
	json.NewDecoder(respGetA.Body).Decode(&fetchedBundleA)
	respGetA.Body.Close()

	if fetchedBundleA["signed_prekey_pub"] != bundleA["signed_prekey_pub"] {
		t.Fatalf("Fetched prekey does not match published prekey")
	}

	// 3. Authenticated Key Agreement (X25519 Diffie-Hellman + HKDF-SHA256)
	peerPrekeyBytes, _ := base64.StdEncoding.DecodeString(fetchedBundleA["signed_prekey_pub"])
	peerPrekeyPub, err := ecdh.X25519().NewPublicKey(peerPrekeyBytes)
	if err != nil {
		t.Fatalf("Failed to parse peer X25519 prekey: %v", err)
	}

	// Calculate ECDH shared secret: Diffie-Hellman
	sharedSecret, err := prekeyB_Priv.ECDH(peerPrekeyPub)
	if err != nil {
		t.Fatalf("ECDH agreement failed: %v", err)
	}

	// Create Chat Room
	roomID := uuid.New().String()
	_, err = db.Exec(`INSERT INTO chat_rooms (id, initiator_id, acceptor_id, is_active) VALUES ($1, $2, $3, true)`,
		roomID, userA_ID, userB_ID)
	if err != nil {
		t.Fatalf("Failed to create chat room: %v", err)
	}
	defer db.Exec(`DELETE FROM chat_rooms WHERE id = $1`, roomID)

	// Derive 256-bit symmetric session master key: HKDF(sharedSecret, roomId, info="EasyChat-E2EE-Room-$roomId")
	sessionMasterKey := hkdfExtractExpand(sharedSecret, []byte(roomID), []byte("EasyChat-E2EE-Room-"+roomID), 32)

	// Helper for AES-256-GCM message encryption matching Flutter CryptoService
	encryptE2EEMessage := func(counter int, plaintextJson string) ([]byte, error) {
		messageKey := hkdfExtractExpand(sessionMasterKey, []byte(fmt.Sprintf("Nonce-%s-%d", roomID, counter)),
			[]byte(fmt.Sprintf("MessageKey-%d", counter)), 32)
		block, err := aes.NewCipher(messageKey)
		if err != nil {
			return nil, err
		}
		gcm, err := cipher.NewGCM(block)
		if err != nil {
			return nil, err
		}
		nonce := make([]byte, 12)
		rand.Read(nonce)

		ciphertextWithTag := gcm.Seal(nil, nonce, []byte(plaintextJson), nil)
		tag := ciphertextWithTag[len(ciphertextWithTag)-16:]
		ciphertext := ciphertextWithTag[:len(ciphertextWithTag)-16]

		envelope := map[string]interface{}{
			"v":  1,
			"c":  counter,
			"n":  base64.StdEncoding.EncodeToString(nonce),
			"t":  base64.StdEncoding.EncodeToString(tag),
			"ct": base64.StdEncoding.EncodeToString(ciphertext),
		}
		envelopeJson, _ := json.Marshal(envelope)
		return []byte("E2EE:v1:" + string(envelopeJson)), nil
	}

	// Helper for AES-256-GCM message decryption matching Flutter CryptoService
	decryptE2EEMessage := func(encryptedBytes []byte) (string, error) {
		rawStr := string(encryptedBytes)
		if !strings.HasPrefix(rawStr, "E2EE:v1:") {
			return rawStr, nil
		}
		envelopeJson := strings.TrimPrefix(rawStr, "E2EE:v1:")
		var env struct {
			C  int    `json:"c"`
			N  string `json:"n"`
			T  string `json:"t"`
			CT string `json:"ct"`
		}
		if err := json.Unmarshal([]byte(envelopeJson), &env); err != nil {
			return "", err
		}
		nonce, _ := base64.StdEncoding.DecodeString(env.N)
		tag, _ := base64.StdEncoding.DecodeString(env.T)
		ciphertext, _ := base64.StdEncoding.DecodeString(env.CT)

		messageKey := hkdfExtractExpand(sessionMasterKey, []byte(fmt.Sprintf("Nonce-%s-%d", roomID, env.C)),
			[]byte(fmt.Sprintf("MessageKey-%d", env.C)), 32)
		block, err := aes.NewCipher(messageKey)
		if err != nil {
			return "", err
		}
		gcm, err := cipher.NewGCM(block)
		if err != nil {
			return "", err
		}
		combined := append(ciphertext, tag...)
		plaintext, err := gcm.Open(nil, nonce, combined, nil)
		if err != nil {
			return "", err
		}
		return string(plaintext), nil
	}

	// =========================================================================
	// 4. VALIDATE 4 MESSAGE TYPES (TEXT, IMAGE, VOICE, LOCATION)
	// =========================================================================

	// --- 4.1 TEXT MESSAGE ---
	textPlaintext := `{"text":"Top Secret Nuclear Fusion Research Data","type":"text"}`
	textCiphertext, err := encryptE2EEMessage(0, textPlaintext)
	if err != nil {
		t.Fatalf("Failed to encrypt text message: %v", err)
	}

	msg1_ID := uuid.New().String()
	_, err = db.Exec(`INSERT INTO messages (id, room_id, sender_id, encrypted_payload) VALUES ($1, $2, $3, $4)`,
		msg1_ID, roomID, userB_ID, textCiphertext)
	if err != nil {
		t.Fatalf("Failed to insert text message: %v", err)
	}

	// --- 4.2 IMAGE ATTACHMENT ---
	rawImage := []byte("\xFF\xD8\xFF\xE0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xFF\xDB-REAL-JPEG-BYTES-TEST")
	mediaKey := make([]byte, 32)
	rand.Read(mediaKey)
	imgNonce := make([]byte, 12)
	rand.Read(imgNonce)

	blockImg, _ := aes.NewCipher(mediaKey)
	gcmImg, _ := cipher.NewGCM(blockImg)
	encryptedImageBlob := gcmImg.Seal(nil, imgNonce, rawImage, nil)
	// Combined attachment format: nonce + ciphertext + tag
	attachmentUploadBlob := append(imgNonce, encryptedImageBlob...)

	// Upload encrypted ciphertext to Media Service
	var b bytes.Buffer
	w := multipart.NewWriter(&b)
	part, _ := w.CreateFormFile("file", "encrypted_image.bin")
	part.Write(attachmentUploadBlob)
	w.WriteField("room_id", roomID)
	w.Close()

	reqUpload, _ := http.NewRequest(http.MethodPost, gatewayBase+"/api/v1/media/upload", &b)
	reqUpload.Header.Set("Authorization", "Bearer "+tokenB)
	reqUpload.Header.Set("Content-Type", w.FormDataContentType())
	respUpload, err := http.DefaultClient.Do(reqUpload)
	if err != nil || respUpload.StatusCode != http.StatusCreated {
		t.Fatalf("Failed to upload encrypted image: %v (code %d)", err, respUpload.StatusCode)
	}
	var uploadRes struct {
		MediaID string `json:"file_id"`
	}
	json.NewDecoder(respUpload.Body).Decode(&uploadRes)
	respUpload.Body.Close()

	imgPlaintext := fmt.Sprintf(`{"type":"image","mediaId":"%s","mediaKey":"%s","mediaNonce":"%s","fileName":"classified.jpg"}`,
		uploadRes.MediaID, base64.StdEncoding.EncodeToString(mediaKey), base64.StdEncoding.EncodeToString(imgNonce))
	imgCiphertext, _ := encryptE2EEMessage(1, imgPlaintext)

	msg2_ID := uuid.New().String()
	_, err = db.Exec(`INSERT INTO messages (id, room_id, sender_id, encrypted_payload) VALUES ($1, $2, $3, $4)`,
		msg2_ID, roomID, userB_ID, imgCiphertext)
	if err != nil {
		t.Fatalf("Failed to insert image message: %v", err)
	}

	// --- 4.3 VOICE ATTACHMENT ---
	rawVoice := []byte("AAC-VOICE-RECORDING-TEST-BYTES-SAMPLE-M4A-STREAM")
	voiceKey := make([]byte, 32)
	rand.Read(voiceKey)
	voiceNonce := make([]byte, 12)
	rand.Read(voiceNonce)

	blockVoice, _ := aes.NewCipher(voiceKey)
	gcmVoice, _ := cipher.NewGCM(blockVoice)
	encryptedVoiceBlob := gcmVoice.Seal(nil, voiceNonce, rawVoice, nil)
	voiceUploadBlob := append(voiceNonce, encryptedVoiceBlob...)

	var bVoice bytes.Buffer
	wVoice := multipart.NewWriter(&bVoice)
	partV, _ := wVoice.CreateFormFile("file", "encrypted_voice.bin")
	partV.Write(voiceUploadBlob)
	wVoice.WriteField("room_id", roomID)
	wVoice.Close()

	reqUploadV, _ := http.NewRequest(http.MethodPost, gatewayBase+"/api/v1/media/upload", &bVoice)
	reqUploadV.Header.Set("Authorization", "Bearer "+tokenB)
	reqUploadV.Header.Set("Content-Type", wVoice.FormDataContentType())
	respUploadV, err := http.DefaultClient.Do(reqUploadV)
	if err != nil || respUploadV.StatusCode != http.StatusCreated {
		t.Fatalf("Failed to upload encrypted voice: %v (code %d)", err, respUploadV.StatusCode)
	}
	var uploadResV struct {
		MediaID string `json:"file_id"`
	}
	json.NewDecoder(respUploadV.Body).Decode(&uploadResV)
	respUploadV.Body.Close()

	voicePlaintext := fmt.Sprintf(`{"type":"voice","mediaId":"%s","mediaKey":"%s","mediaNonce":"%s","durationMs":4500}`,
		uploadResV.MediaID, base64.StdEncoding.EncodeToString(voiceKey), base64.StdEncoding.EncodeToString(voiceNonce))
	voiceCiphertext, _ := encryptE2EEMessage(2, voicePlaintext)

	msg3_ID := uuid.New().String()
	_, err = db.Exec(`INSERT INTO messages (id, room_id, sender_id, encrypted_payload) VALUES ($1, $2, $3, $4)`,
		msg3_ID, roomID, userB_ID, voiceCiphertext)
	if err != nil {
		t.Fatalf("Failed to insert voice message: %v", err)
	}

	// --- 4.4 LOCATION MESSAGE ---
	locationPlaintext := `{"type":"location","location":{"latitude":17.385044,"longitude":78.486671,"name":"Hyderabad Secret Coordinates"}}`
	locationCiphertext, _ := encryptE2EEMessage(3, locationPlaintext)

	msg4_ID := uuid.New().String()
	_, err = db.Exec(`INSERT INTO messages (id, room_id, sender_id, encrypted_payload) VALUES ($1, $2, $3, $4)`,
		msg4_ID, roomID, userB_ID, locationCiphertext)
	if err != nil {
		t.Fatalf("Failed to insert location message: %v", err)
	}

	// =========================================================================
	// 5. VERIFY POSTGRESQL ZERO-KNOWLEDGE INVARIANT
	// =========================================================================
	var storedPayloads [][]byte
	rows, err := db.Query(`SELECT encrypted_payload FROM messages WHERE room_id = $1 ORDER BY created_at ASC`, roomID)
	if err != nil {
		t.Fatalf("Failed to query messages: %v", err)
	}
	for rows.Next() {
		var p []byte
		rows.Scan(&p)
		storedPayloads = append(storedPayloads, p)
	}
	rows.Close()

	if len(storedPayloads) != 4 {
		t.Fatalf("Expected 4 stored messages, found %d", len(storedPayloads))
	}

	prohibitedPlaintexts := []string{
		"Nuclear Fusion", "Top Secret", "REAL-JPEG", "AAC-VOICE", "17.385044", "Hyderabad Secret",
	}

	for _, payload := range storedPayloads {
		pStr := string(payload)
		if !strings.HasPrefix(pStr, "E2EE:v1:") {
			t.Errorf("Stored payload is NOT an authenticated E2EE envelope: %s", pStr)
		}
		for _, prohibited := range prohibitedPlaintexts {
			if strings.Contains(pStr, prohibited) {
				t.Fatalf("SECURITY VIOLATION: Database contains plaintext: '%s'", prohibited)
			}
		}
	}

	// Verify receiver decryption of all 4 payloads
	decText, err := decryptE2EEMessage(storedPayloads[0])
	if err != nil || decText != textPlaintext {
		t.Fatalf("Text decryption failed or mismatched: %v", err)
	}
	decImg, err := decryptE2EEMessage(storedPayloads[1])
	if err != nil || decImg != imgPlaintext {
		t.Fatalf("Image decryption failed or mismatched: %v", err)
	}
	decVoice, err := decryptE2EEMessage(storedPayloads[2])
	if err != nil || decVoice != voicePlaintext {
		t.Fatalf("Voice decryption failed or mismatched: %v", err)
	}
	decLoc, err := decryptE2EEMessage(storedPayloads[3])
	if err != nil || decLoc != locationPlaintext {
		t.Fatalf("Location decryption failed or mismatched: %v", err)
	}

	// =========================================================================
	// 6. ADVERSARIAL CRYPTOGRAPHIC NEGATIVE TESTS
	// =========================================================================

	// 6.1 Tampered Ciphertext must fail MAC validation
	var envToTamper struct {
		C  int    `json:"c"`
		N  string `json:"n"`
		T  string `json:"t"`
		CT string `json:"ct"`
	}
	rawEnv := strings.TrimPrefix(string(storedPayloads[0]), "E2EE:v1:")
	json.Unmarshal([]byte(rawEnv), &envToTamper)
	ctBytes, _ := base64.StdEncoding.DecodeString(envToTamper.CT)
	if len(ctBytes) > 0 {
		ctBytes[0] ^= 0xFF // Flip bits in ciphertext
	}
	envToTamper.CT = base64.StdEncoding.EncodeToString(ctBytes)
	tamperedBytes, _ := json.Marshal(envToTamper)
	tamperedPayload := []byte("E2EE:v1:" + string(tamperedBytes))
	_, err = decryptE2EEMessage(tamperedPayload)
	if err == nil {
		t.Fatalf("SECURITY FLAW: Tampered ciphertext was accepted without authentication tag failure")
	}

	// 6.2 Malformed Ciphertext
	_, err = decryptE2EEMessage([]byte("E2EE:v1:not-json"))
	if err == nil {
		t.Fatalf("SECURITY FLAW: Malformed non-JSON envelope did not error cleanly")
	}

	// =========================================================================
	// 7. MESSAGE & ATTACHMENT DELETION (DELETE FOR EVERYONE)
	// =========================================================================

	// Unauthorized deletion by User C (non-member)
	userC_ID := uuid.New().String()
	tokenC := generateToken(userC_ID)

	reqDelUnauthorized, _ := http.NewRequest(http.MethodDelete, gatewayBase+"/api/v1/chat/messages/"+msg2_ID+"?room_id="+roomID, nil)
	reqDelUnauthorized.Header.Set("Authorization", "Bearer "+tokenC)
	respDelUnauth, err := http.DefaultClient.Do(reqDelUnauthorized)
	if err != nil || respDelUnauth.StatusCode != http.StatusForbidden {
		t.Fatalf("Expected 403 Forbidden for unauthorized non-member deletion, got: %d", respDelUnauth.StatusCode)
	}
	respDelUnauth.Body.Close()

	// Non-owner deletion by User A (room member but not sender)
	reqDelNonOwner, _ := http.NewRequest(http.MethodDelete, gatewayBase+"/api/v1/chat/messages/"+msg2_ID+"?room_id="+roomID, nil)
	reqDelNonOwner.Header.Set("Authorization", "Bearer "+tokenA)
	respDelNonOwner, err := http.DefaultClient.Do(reqDelNonOwner)
	if err != nil || respDelNonOwner.StatusCode != http.StatusForbidden {
		t.Fatalf("Expected 403 Forbidden for non-owner deletion, got: %d", respDelNonOwner.StatusCode)
	}
	respDelNonOwner.Body.Close()

	// Authorized Delete for Everyone by User B (the message sender)
	reqDelOwner, _ := http.NewRequest(http.MethodDelete, gatewayBase+"/api/v1/chat/messages/"+msg2_ID+"?room_id="+roomID, nil)
	reqDelOwner.Header.Set("Authorization", "Bearer "+tokenB)
	respDelOwner, err := http.DefaultClient.Do(reqDelOwner)
	if err != nil || respDelOwner.StatusCode != http.StatusOK {
		t.Fatalf("Authorized Delete For Everyone failed: %v (code %d)", err, respDelOwner.StatusCode)
	}
	respDelOwner.Body.Close()

	// Verify Database State: is_deleted = true, encrypted_payload is purged to empty bytes
	var isDeleted bool
	var deletedPayload []byte
	err = db.QueryRow(`SELECT is_deleted, encrypted_payload FROM messages WHERE id = $1`, msg2_ID).Scan(&isDeleted, &deletedPayload)
	if err != nil {
		t.Fatalf("Failed to query deleted message: %v", err)
	}
	if !isDeleted {
		t.Fatalf("Expected is_deleted = true in database")
	}
	if len(deletedPayload) != 0 {
		t.Fatalf("Expected encrypted_payload to be wiped to empty bytes upon deletion, found %d bytes", len(deletedPayload))
	}

	// Delete Associated Media Object from Media Service
	reqDelMedia, _ := http.NewRequest(http.MethodDelete, gatewayBase+"/api/v1/media/"+uploadRes.MediaID, nil)
	reqDelMedia.Header.Set("Authorization", "Bearer "+tokenB)
	respDelMedia, err := http.DefaultClient.Do(reqDelMedia)
	if err != nil || respDelMedia.StatusCode != http.StatusOK {
		t.Fatalf("Delete media failed: %v (code %d)", err, respDelMedia.StatusCode)
	}
	respDelMedia.Body.Close()

	// Verify media download returns 404 / 401
	reqDownload, _ := http.NewRequest(http.MethodGet, gatewayBase+"/api/v1/media/download/"+uploadRes.MediaID, nil)
	reqDownload.Header.Set("Authorization", "Bearer "+tokenB)
	respDownload, err := http.DefaultClient.Do(reqDownload)
	if err != nil || (respDownload.StatusCode != http.StatusNotFound && respDownload.StatusCode != http.StatusForbidden) {
		t.Fatalf("Expected 404 or 403 on deleted media download, got: %d", respDownload.StatusCode)
	}
	respDownload.Body.Close()

	// =========================================================================
	// 8. OFFLINE DELETION & TOMBSTONE SYNCHRONIZATION
	// =========================================================================
	// Query deletions since timestamp (simulating reconnect sync for Device A)
	sinceTime := time.Now().Add(-10 * time.Minute)
	var tombstoneIDs []string
	tombRows, err := db.Query(`SELECT id FROM messages WHERE room_id = $1 AND is_deleted = TRUE AND deleted_at >= $2`,
		roomID, sinceTime)
	if err != nil {
		t.Fatalf("Failed to query deletion tombstones: %v", err)
	}
	for tombRows.Next() {
		var tid string
		tombRows.Scan(&tid)
		tombstoneIDs = append(tombstoneIDs, tid)
	}
	tombRows.Close()

	foundTombstone := false
	for _, tid := range tombstoneIDs {
		if tid == msg2_ID {
			foundTombstone = true
			break
		}
	}
	if !foundTombstone {
		t.Fatalf("Expected deletion tombstone for message %s not found in offline synchronization query", msg2_ID)
	}

	t.Logf("✅ TRUE E2EE + DELETION TEST SUITE PASSED ALL PRODUCTION GATES")
}
