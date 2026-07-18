package main

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	_ "github.com/lib/pq"
	"github.com/gorilla/websocket"
	"github.com/redis/go-redis/v9"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"

	genv1 "nearby/backend/internal/gen/v1"
)

const (
	gatewayURL  = "http://localhost:8090"
	gatewayWS   = "ws://localhost:8090/ws"
	nearbygRPC  = "localhost:8084"
	postgresDSN = "postgres://nearby_user:nearby_secure_pass@127.0.0.1:54322/nearby_connect?sslmode=disable"
	redisAddr   = "localhost:6379"

	testPassword = "Password123!"
	roomID       = "00000000-0000-0000-0000-000000000001"
)

type UserRegReq struct {
	DeviceID  string `json:"device_id"`
	Pseudonym string `json:"pseudonym"`
	Password  string `json:"password"`
	Role      string `json:"role"`
}

type LoginReq struct {
	DeviceID string `json:"device_id"`
	Password string `json:"password"`
}

type LoginResp struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
}

// WebSocket message structures matching domain.go and server.go
type WSMessage struct {
	ID               string    `json:"message_id,omitempty"`
	RoomID           string    `json:"room_id,omitempty"`
	SenderID         string    `json:"sender_id,omitempty"`
	EncryptedPayload []byte    `json:"encrypted_payload,omitempty"`
	IdempotencyKey   string    `json:"idempotency_key,omitempty"`
	CreatedAt        time.Time `json:"created_at,omitempty"`
}

type WSReadReceipt struct {
	MessageID string    `json:"message_id,omitempty"`
	RoomID    string    `json:"room_id,omitempty"`
	UserID    string    `json:"user_id,omitempty"`
	Status    string    `json:"status,omitempty"` // "DELIVERED" or "READ"
	Timestamp time.Time `json:"timestamp,omitempty"`
}

type WSTypingIndicator struct {
	RoomID   string `json:"room_id,omitempty"`
	UserID   string `json:"user_id,omitempty"`
	IsTyping bool   `json:"is_typing,omitempty"`
}

type WSPacket struct {
	Type               string             `json:"type"` // MESSAGE, RECEIPT, TYPING, SUBSCRIBE_ROOM, UNSUBSCRIBE_ROOM, RECONNECT
	Message            *WSMessage         `json:"message,omitempty"`
	Receipt            *WSReadReceipt     `json:"receipt,omitempty"`
	Typing             *WSTypingIndicator `json:"typing,omitempty"`
	ReconnectTimestamp string             `json:"reconnect_timestamp,omitempty"`
	RoomID             string             `json:"room_id,omitempty"`
	Limit              int                `json:"limit,omitempty"`
	Offset             int                `json:"offset,omitempty"`
}

type SimClient struct {
	DeviceID  string
	Pseudonym string
	Token     string
	UserID    string
	Conn      *websocket.Conn
	MsgChan   chan *WSPacket
	wg        sync.WaitGroup
	ctx       context.Context
	cancel    context.CancelFunc
}

func NewSimClient(deviceID, pseudonym string) *SimClient {
	ctx, cancel := context.WithCancel(context.Background())
	return &SimClient{
		DeviceID:  deviceID,
		Pseudonym: pseudonym,
		MsgChan:   make(chan *WSPacket, 100),
		ctx:       ctx,
		cancel:    cancel,
	}
}

func (c *SimClient) RegisterAndLogin() error {
	time.Sleep(1 * time.Second) // prevent rate limiting burst

	var resp *http.Response
	var err error

	// Register retry loop
	for i := 0; i < 5; i++ {
		regBody, _ := json.Marshal(UserRegReq{
			DeviceID:  c.DeviceID,
			Pseudonym: c.Pseudonym,
			Password:  testPassword,
			Role:      "user",
		})
		resp, err = http.Post(gatewayURL+"/api/v1/auth/register", "application/json", bytes.NewBuffer(regBody))
		if err == nil {
			if resp.StatusCode == http.StatusTooManyRequests {
				resp.Body.Close()
				time.Sleep(2 * time.Second)
				continue
			}
			break
		}
		time.Sleep(1 * time.Second)
	}

	if err != nil {
		return fmt.Errorf("registration HTTP error: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated && resp.StatusCode != http.StatusConflict {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("registration returned code %d, body: %s", resp.StatusCode, string(body))
	}

	// Login retry loop
	var respLogin *http.Response
	for i := 0; i < 5; i++ {
		loginBody, _ := json.Marshal(LoginReq{
			DeviceID: c.DeviceID,
			Password: testPassword,
		})
		respLogin, err = http.Post(gatewayURL+"/api/v1/auth/login", "application/json", bytes.NewBuffer(loginBody))
		if err == nil {
			if respLogin.StatusCode == http.StatusTooManyRequests {
				respLogin.Body.Close()
				time.Sleep(2 * time.Second)
				continue
			}
			break
		}
		time.Sleep(1 * time.Second)
	}

	if err != nil {
		return fmt.Errorf("login HTTP error: %w", err)
	}
	defer respLogin.Body.Close()
	if respLogin.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(respLogin.Body)
		return fmt.Errorf("login returned code %d, body: %s", respLogin.StatusCode, string(body))
	}

	var lr LoginResp
	if err := json.NewDecoder(respLogin.Body).Decode(&lr); err != nil {
		return fmt.Errorf("failed to parse login response: %w", err)
	}
	c.Token = lr.AccessToken
	return nil
}

func (c *SimClient) ConnectWS() error {
	u, err := url.Parse(gatewayWS)
	if err != nil {
		return err
	}
	q := u.Query()
	q.Set("token", c.Token)
	u.RawQuery = q.Encode()

	dialer := websocket.DefaultDialer
	conn, _, err := dialer.Dial(u.String(), nil)
	if err != nil {
		return fmt.Errorf("websocket connection failure: %w", err)
	}
	c.Conn = conn

	// Spawn receiver goroutine
	c.wg.Add(1)
	go func() {
		defer c.wg.Done()
		for {
			select {
			case <-c.ctx.Done():
				return
			default:
				_, message, err := c.Conn.ReadMessage()
				if err != nil {
					// Check if context was cancelled (intended disconnect)
					select {
					case <-c.ctx.Done():
						return
					default:
					}
					log.Printf("[%s] WebSocket read error: %v", c.Pseudonym, err)
					return
				}
				var packet WSPacket
				if err := json.Unmarshal(message, &packet); err != nil {
					log.Printf("[%s] Error unmarshaling WebSocket packet: %v", c.Pseudonym, err)
					continue
				}
				c.MsgChan <- &packet
			}
		}
	}()

	return nil
}

func (c *SimClient) DisconnectWS() {
	c.cancel()
	if c.Conn != nil {
		_ = c.Conn.Close()
	}
	c.wg.Wait()
	// Recreate context for potential reconnection
	c.ctx, c.cancel = context.WithCancel(context.Background())
}

func (c *SimClient) SendWS(packet *WSPacket) error {
	payload, err := json.Marshal(packet)
	if err != nil {
		return err
	}
	return c.Conn.WriteMessage(websocket.TextMessage, payload)
}

func main() {
	fmt.Println("=================================================================")
	fmt.Println("NEARBY CONNECT TWO-DEVICE END-TO-END VALIDATION RUNNER")
	fmt.Println("=================================================================")

	// 1. Initialize DB and Redis
	db, err := sql.Open("postgres", postgresDSN)
	if err != nil {
		log.Fatalf("Failed to connect to Postgres: %v", err)
	}
	defer db.Close()
	if err := db.Ping(); err != nil {
		log.Fatalf("Postgres ping failed: %v", err)
	}
	fmt.Println("✓ Connected to PostgreSQL Database")

	rdb := redis.NewClient(&redis.Options{Addr: redisAddr})
	defer rdb.Close()
	if err := rdb.Ping(context.Background()).Err(); err != nil {
		log.Fatalf("Redis ping failed: %v", err)
	}
	fmt.Println("✓ Connected to Redis Cache")

	// Clean up previous simulation records
	_, err = db.Exec("DELETE FROM users WHERE device_id IN ('device_sim_a', 'device_sim_b')")
	if err != nil {
		log.Fatalf("Failed to clean up previous users: %v", err)
	}
	_ = rdb.Del(context.Background(), "nearby:locations")
	fmt.Println("✓ Cleaned up existing simulation DB and Redis states")

	// Initialize simulated clients
	clientA := NewSimClient("device_sim_a", "Alice")
	clientB := NewSimClient("device_sim_b", "Bob")

	// ======================================================
	// Phase 1 — User Lifecycle & Device Onboarding
	// ======================================================
	fmt.Println("\n--- PHASE 1: User Lifecycle & Device Onboarding ---")

	if err := clientA.RegisterAndLogin(); err != nil {
		log.Fatalf("Client A Registration/Login failed: %v", err)
	}
	fmt.Println("✓ Registered and logged in Alice (Client A)")

	if err := clientB.RegisterAndLogin(); err != nil {
		log.Fatalf("Client B Registration/Login failed: %v", err)
	}
	fmt.Println("✓ Registered and logged in Bob (Client B)")

	// Retrieve User IDs from database
	err = db.QueryRow("SELECT id::text FROM users WHERE device_id = $1", clientA.DeviceID).Scan(&clientA.UserID)
	if err != nil {
		log.Fatalf("Failed to get Alice User ID: %v", err)
	}
	err = db.QueryRow("SELECT id::text FROM users WHERE device_id = $1", clientB.DeviceID).Scan(&clientB.UserID)
	if err != nil {
		log.Fatalf("Failed to get Bob User ID: %v", err)
	}
	fmt.Printf("  Alice User ID: %s\n", clientA.UserID)
	fmt.Printf("  Bob User ID: %s\n", clientB.UserID)

	// Establish WebSocket connections
	if err := clientA.ConnectWS(); err != nil {
		log.Fatalf("Client A WebSocket connection failed: %v", err)
	}
	fmt.Println("✓ Alice established active WebSocket connection")

	if err := clientB.ConnectWS(); err != nil {
		log.Fatalf("Client B WebSocket connection failed: %v", err)
	}
	fmt.Println("✓ Bob established active WebSocket connection")

	// ======================================================
	// Phase 2 — Visibility & Privacy Controls
	// ======================================================
	fmt.Println("\n--- PHASE 2: Visibility & Privacy Controls ---")

	// Setup gRPC Nearby Client
	conn, err := grpc.Dial(nearbygRPC, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		log.Fatalf("Failed to dial Nearby gRPC service: %v", err)
	}
	defer conn.Close()
	nearbyCli := genv1.NewNearbyServiceClient(conn)

	// Set base locations in Redis Geo (Alice at SF center, Bob nearby)
	aliceLat, aliceLon := 37.7749, -122.4194
	_ = aliceLon
	bobLat, bobLon := 37.7752, -122.4194 // ~33 meters away

	err = rdb.GeoAdd(context.Background(), "nearby:locations", &redis.GeoLocation{
		Name:      clientB.UserID,
		Latitude:  bobLat,
		Longitude: bobLon,
	}).Err()
	if err != nil {
		log.Fatalf("Failed to set Bob location in Redis Geo Set: %v", err)
	}
	_ = rdb.Set(context.Background(), "nearby:location:ttl:"+clientB.UserID, "1", 60*time.Second).Err()

	// Ensure Bob is visible in db
	_, _ = db.Exec("UPDATE presence SET is_visible = true WHERE user_id = $1", clientB.UserID)

	// Debug prints
	var isVisible bool
	var status string
	_ = db.QueryRow("SELECT status FROM users WHERE id = $1", clientB.UserID).Scan(&status)
	_ = db.QueryRow("SELECT is_visible FROM presence WHERE user_id = $1", clientB.UserID).Scan(&isVisible)
	log.Printf("Debug DB Check: Bob status=%s, is_visible=%v", status, isVisible)

	var pCount, presCount, setStr int
	_ = db.QueryRow("SELECT count(*) FROM profiles WHERE user_id = $1", clientB.UserID).Scan(&pCount)
	_ = db.QueryRow("SELECT count(*) FROM presence WHERE user_id = $1", clientB.UserID).Scan(&presCount)
	_ = db.QueryRow("SELECT count(*) FROM user_settings WHERE user_id = $1", clientB.UserID).Scan(&setStr)
	log.Printf("Debug DB Check Bob: profiles=%d, presence=%d, settings=%d", pCount, presCount, setStr)

	var pCountA, presCountA, setStrA int
	_ = db.QueryRow("SELECT count(*) FROM profiles WHERE user_id = $1", clientA.UserID).Scan(&pCountA)
	_ = db.QueryRow("SELECT count(*) FROM presence WHERE user_id = $1", clientA.UserID).Scan(&presCountA)
	_ = db.QueryRow("SELECT count(*) FROM user_settings WHERE user_id = $1", clientA.UserID).Scan(&setStrA)
	log.Printf("Debug DB Check Alice: profiles=%d, presence=%d, settings=%d", pCountA, presCountA, setStrA)

	res, rerr := rdb.GeoSearchLocation(context.Background(), "nearby:locations", &redis.GeoSearchLocationQuery{
		GeoSearchQuery: redis.GeoSearchQuery{
			Longitude:  aliceLon,
			Latitude:   aliceLat,
			Radius:     150,
			RadiusUnit: "m",
		},
		WithDist: true,
	}).Result()
	log.Printf("Debug Redis Check: Alice=(%v,%v) GeoSearch found %d users: %+v, err: %v", aliceLat, aliceLon, len(res), res, rerr)

	// Test 1: Visibility ON -> Bob should be discoverable by Alice
	respDiscover, err := nearbyCli.GetNearbyUsers(context.Background(), &genv1.GetNearbyUsersRequest{
		UserId:       clientA.UserID,
		H3Index:      "8a2a1072b59ffff", // maps to 37.7749, -122.4194
		RadiusMeters: 150,
	})
	if err != nil {
		log.Fatalf("gRPC Discovery failed: %v", err)
	}
	foundBob := false
	for _, u := range respDiscover.Users {
		if u.UserId == clientB.UserID {
			foundBob = true
			break
		}
	}
	if !foundBob {
		log.Fatalf("FAIL: Bob was not discovered by Alice while visibility was ON")
	}
	fmt.Println("✓ Visibility ON: Bob is successfully discovered by Alice")

	// Test 2: Visibility OFF -> Bob should be hidden from Alice
	_, _ = db.Exec("UPDATE presence SET is_visible = false WHERE user_id = $1", clientB.UserID)
	respDiscover, err = nearbyCli.GetNearbyUsers(context.Background(), &genv1.GetNearbyUsersRequest{
		UserId:       clientA.UserID,
		H3Index:      "8a2a1072b59ffff",
		RadiusMeters: 150,
	})
	if err != nil {
		log.Fatalf("gRPC Discovery failed: %v", err)
	}
	foundBob = false
	for _, u := range respDiscover.Users {
		if u.UserId == clientB.UserID {
			foundBob = true
			break
		}
	}
	if foundBob {
		log.Fatalf("FAIL: Bob was discovered by Alice while visibility was OFF")
	}
	fmt.Println("✓ Visibility OFF: Bob is successfully hidden from Alice's discovery list")

	// Restore Bob's visibility
	_, _ = db.Exec("UPDATE presence SET is_visible = true WHERE user_id = $1", clientB.UserID)

	// Test 3: Blocked users -> Bob should be hidden from Alice if Alice blocks Bob
	_, err = db.Exec("INSERT INTO user_blocks (blocker_id, blocked_id) VALUES ($1, $2)", clientA.UserID, clientB.UserID)
	if err != nil {
		log.Fatalf("Failed to insert block: %v", err)
	}
	respDiscover, err = nearbyCli.GetNearbyUsers(context.Background(), &genv1.GetNearbyUsersRequest{
		UserId:       clientA.UserID,
		H3Index:      "8a2a1072b59ffff",
		RadiusMeters: 150,
	})
	if err != nil {
		log.Fatalf("gRPC Discovery failed: %v", err)
	}
	foundBob = false
	for _, u := range respDiscover.Users {
		if u.UserId == clientB.UserID {
			foundBob = true
			break
		}
	}
	if foundBob {
		log.Fatalf("FAIL: Bob was discovered by Alice after being blocked")
	}
	fmt.Println("✓ Blocked Users: Bob is successfully hidden from Alice after being blocked")

	// Unblock Bob
	_, err = db.Exec("DELETE FROM user_blocks WHERE blocker_id = $1 AND blocked_id = $2", clientA.UserID, clientB.UserID)
	if err != nil {
		log.Fatalf("Failed to delete block: %v", err)
	}
	respDiscover, err = nearbyCli.GetNearbyUsers(context.Background(), &genv1.GetNearbyUsersRequest{
		UserId:       clientA.UserID,
		H3Index:      "8a2a1072b59ffff",
		RadiusMeters: 150,
	})
	if err != nil {
		log.Fatalf("gRPC Discovery failed: %v", err)
	}
	foundBob = false
	for _, u := range respDiscover.Users {
		if u.UserId == clientB.UserID {
			foundBob = true
			break
		}
	}
	if !foundBob {
		log.Fatalf("FAIL: Bob was not discovered by Alice after being unblocked")
	}
	fmt.Println("✓ Blocked Users: Bob is successfully visible again after being unblocked")

	// ======================================================
	// Phase 3 — Nearby Discovery (Radius Filtering)
	// ======================================================
	fmt.Println("\n--- PHASE 3: Proximity & Nearby Discovery ---")

	distances := []int{50, 100, 150, 200, 300} // Test distances in meters
	discoveryRadius := 150                     // Query discovery radius = 150 meters

	for _, d := range distances {
		// Calculate Bob coordinates at exactly 'd' meters from Alice (latitude: 1 degree ~ 111,000 meters)
		deltaLat := float64(d) / 111000.0
		bobLatTest := aliceLat + deltaLat

		// Update Bob location in Redis
		err = rdb.GeoAdd(context.Background(), "nearby:locations", &redis.GeoLocation{
			Name:      clientB.UserID,
			Latitude:  bobLatTest,
			Longitude: bobLon,
		}).Err()
		if err != nil {
			log.Fatalf("Failed to update Bob location at %dm: %v", d, err)
		}

		// Perform Discovery
		respDiscover, err = nearbyCli.GetNearbyUsers(context.Background(), &genv1.GetNearbyUsersRequest{
			UserId:       clientA.UserID,
			H3Index:      "8a2a1072b59ffff",
			RadiusMeters: int32(discoveryRadius),
		})
		if err != nil {
			log.Fatalf("gRPC Discovery failed at distance %dm: %v", d, err)
		}

		foundBob = false
		for _, u := range respDiscover.Users {
			if u.UserId == clientB.UserID {
				foundBob = true
				break
			}
		}

		// Assertions based on proximity threshold
		if d <= discoveryRadius {
			if !foundBob {
				log.Fatalf("FAIL: Bob at %dm was NOT discovered (Discovery Radius: %dm)", d, discoveryRadius)
			}
			fmt.Printf("✓ Distance %3dm: Bob is DISCOVERED (expected: YES)\n", d)
		} else {
			if foundBob {
				log.Fatalf("FAIL: Bob at %dm WAS discovered (Discovery Radius: %dm)", d, discoveryRadius)
			}
			fmt.Printf("✓ Distance %3dm: Bob is HIDDEN (expected: NO)\n", d)
		}
	}

	// ======================================================
	// Phase 4 — Presence State
	// ======================================================
	fmt.Println("\n--- PHASE 4: Presence State Lifecycle ---")

	// Trigger online presence status update via direct HTTP gateway presence heartbeat
	hbBody := `{"state":"online","h3_index":"8a2a1072b59ffff"}`
	req, _ := http.NewRequest("POST", gatewayURL+"/api/v1/presence/heartbeat", strings.NewReader(hbBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+clientA.Token)
	respHB, err := http.DefaultClient.Do(req)
	if err != nil || respHB.StatusCode != http.StatusOK {
		log.Fatalf("Alice online heartbeat failed: status: %d, err: %v", respHB.StatusCode, err)
	}

	var isOnline bool
	err = db.QueryRow("SELECT is_online FROM presence WHERE user_id = $1", clientA.UserID).Scan(&isOnline)
	if err != nil || !isOnline {
		log.Fatalf("FAIL: Alice is not marked ONLINE in presence table")
	}
	fmt.Println("✓ Heartbeat: Alice successfully marked ONLINE in PostgreSQL")

	// Trigger offline status
	hbBody = `{"state":"offline","h3_index":"8a2a1072b59ffff"}`
	req, _ = http.NewRequest("POST", gatewayURL+"/api/v1/presence/heartbeat", strings.NewReader(hbBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+clientA.Token)
	respHB, _ = http.DefaultClient.Do(req)
	_ = db.QueryRow("SELECT is_online FROM presence WHERE user_id = $1", clientA.UserID).Scan(&isOnline)
	if isOnline {
		log.Fatalf("FAIL: Alice is still marked ONLINE in presence table after offline heartbeat")
	}
	fmt.Println("✓ Heartbeat: Alice successfully marked OFFLINE in PostgreSQL")

	// Restore online state
	hbBody = `{"state":"online","h3_index":"8a2a1072b59ffff"}`
	req, _ = http.NewRequest("POST", gatewayURL+"/api/v1/presence/heartbeat", strings.NewReader(hbBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+clientA.Token)
	_, _ = http.DefaultClient.Do(req)

	// ======================================================
	// Phase 5 & 6 — Chat & Messaging Workflow
	// ======================================================
	fmt.Println("\n--- PHASE 5 & 6: Chat & Messaging ---")

	// Pre-create room in DB to satisfy constraints
	_, err = db.Exec("INSERT INTO chat_rooms (id, initiator_id, acceptor_id, is_active) VALUES ($1, $2, $3, true)",
		roomID, clientA.UserID, clientB.UserID)
	if err != nil {
		log.Fatalf("Failed to pre-create chat room in Postgres: %v", err)
	}
	fmt.Println("✓ Pre-created chat room between Alice and Bob in PostgreSQL")

	// Subscribe Bob to Room typing indicators
	err = clientB.SendWS(&WSPacket{
		Type:   "SUBSCRIBE_ROOM",
		RoomID: roomID,
	})
	if err != nil {
		log.Fatalf("Bob failed to send SUBSCRIBE_ROOM packet: %v", err)
	}
	fmt.Println("✓ Bob subscribed to chat room typing events over WebSocket")

	// Alice sends typing indicator
	err = clientA.SendWS(&WSPacket{
		Type: "TYPING",
		Typing: &WSTypingIndicator{
			RoomID:   roomID,
			UserID:   clientA.UserID,
			IsTyping: true,
		},
	})
	if err != nil {
		log.Fatalf("Alice failed to send TYPING event: %v", err)
	}

	// Verify Bob receives the typing event
	select {
	case p := <-clientB.MsgChan:
		if p.Type != "TYPING" || p.Typing == nil || !p.Typing.IsTyping || p.Typing.UserID != clientA.UserID {
			log.Fatalf("FAIL: Bob received unexpected packet instead of Alice typing: %+v", p)
		}
		fmt.Println("✓ Bob received Alice's typing indicator over WebSocket")
	case <-time.After(3 * time.Second):
		log.Fatalf("FAIL: Bob did not receive typing indicator within timeout")
	}

	// Alice sends text message
	msgPayload := "Hello, Bob!"
	encPayload := []byte(msgPayload)
	messageID := "11111111-1111-1111-1111-111111111111"
	idempKey := "idemp_msg_key_1"

	err = clientA.SendWS(&WSPacket{
		Type: "MESSAGE",
		Message: &WSMessage{
			ID:               messageID,
			RoomID:           roomID,
			SenderID:         clientA.UserID,
			EncryptedPayload: encPayload,
			IdempotencyKey:   idempKey,
		},
	})
	if err != nil {
		log.Fatalf("Alice failed to send MESSAGE over WebSocket: %v", err)
	}

	// Verify Bob receives the message
	var receivedMsg *WSMessage
	select {
	case p := <-clientB.MsgChan:
		if p.Type != "MESSAGE" || p.Message == nil {
			log.Fatalf("FAIL: Bob received unexpected packet instead of Message: %+v", p)
		}
		receivedMsg = p.Message
		if string(receivedMsg.EncryptedPayload) != msgPayload {
			log.Fatalf("FAIL: Bob received incorrect message payload: %s", string(receivedMsg.EncryptedPayload))
		}
		fmt.Printf("✓ Bob received message: '%s' (Instant Delivery)\n", string(receivedMsg.EncryptedPayload))
	case <-time.After(5 * time.Second):
		log.Fatalf("FAIL: Bob did not receive message within timeout (Delivery failed)")
	}

	// Verify persistence in PostgreSQL
	var dbPayload []byte
	err = db.QueryRow("SELECT encrypted_payload FROM messages WHERE id = $1", messageID).Scan(&dbPayload)
	if err != nil || string(dbPayload) != msgPayload {
		log.Fatalf("FAIL: Message not persisted or incorrect in DB: err=%v", err)
	}
	fmt.Println("✓ Message persisted in PostgreSQL database")

	// Bob sends delivery receipt back to Alice
	err = clientB.SendWS(&WSPacket{
		Type: "RECEIPT",
		Receipt: &WSReadReceipt{
			MessageID: messageID,
			RoomID:    roomID,
			UserID:    clientB.UserID,
			Status:    "DELIVERED",
			Timestamp: time.Now(),
		},
	})
	if err != nil {
		log.Fatalf("Bob failed to send DELIVERED receipt: %v", err)
	}

	// Verify Alice receives the delivery receipt
	select {
	case p := <-clientA.MsgChan:
		if p.Type != "RECEIPT" || p.Receipt == nil || p.Receipt.Status != "DELIVERED" {
			log.Fatalf("FAIL: Alice received unexpected packet instead of DELIVERED receipt: %+v", p)
		}
		fmt.Println("✓ Alice received Bob's DELIVERED receipt")
	case <-time.After(3 * time.Second):
		log.Fatalf("FAIL: Alice did not receive DELIVERED receipt within timeout")
	}

	// Bob sends read receipt back to Alice
	err = clientB.SendWS(&WSPacket{
		Type: "RECEIPT",
		Receipt: &WSReadReceipt{
			MessageID: messageID,
			RoomID:    roomID,
			UserID:    clientB.UserID,
			Status:    "READ",
			Timestamp: time.Now(),
		},
	})
	if err != nil {
		log.Fatalf("Bob failed to send READ receipt: %v", err)
	}

	// Verify Alice receives the read receipt
	select {
	case p := <-clientA.MsgChan:
		if p.Type != "RECEIPT" || p.Receipt == nil || p.Receipt.Status != "READ" {
			log.Fatalf("FAIL: Alice received unexpected packet instead of READ receipt: %+v", p)
		}
		fmt.Println("✓ Alice received Bob's READ receipt")
	case <-time.After(3 * time.Second):
		log.Fatalf("FAIL: Alice did not receive READ receipt within timeout")
	}

	// Verify receipt persistence in PostgreSQL
	var dbReceiptStatus string
	err = db.QueryRow("SELECT status FROM message_receipts WHERE message_id = $1 AND user_id = $2", messageID, clientB.UserID).Scan(&dbReceiptStatus)
	if err != nil || dbReceiptStatus != "READ" {
		log.Fatalf("FAIL: Receipt not persisted or incorrect in DB: err=%v", err)
	}
	fmt.Println("✓ Receipt persisted as 'READ' in PostgreSQL database")

	// ======================================================
	// Phase 7 — Disconnect & Recovery
	// ======================================================
	fmt.Println("\n--- PHASE 7: Disconnect & Recovery ---")

	// Simulate Client B going offline (disconnect WebSocket)
	clientB.DisconnectWS()
	fmt.Println("✓ Bob disconnected WebSocket connection (Simulated Network Outage)")

	// Capture timestamp before sending offline message
	timeBeforeOfflineMsg := time.Now().Add(-1 * time.Second)

	// Alice sends message 2 while Bob is offline
	msg2Payload := "Are you still there, Bob?"
	message2ID := "22222222-2222-2222-2222-222222222222"
	idemp2Key := "idemp_msg_key_2"

	err = clientA.SendWS(&WSPacket{
		Type: "MESSAGE",
		Message: &WSMessage{
			ID:               message2ID,
			RoomID:           roomID,
			SenderID:         clientA.UserID,
			EncryptedPayload: []byte(msg2Payload),
			IdempotencyKey:   idemp2Key,
		},
	})
	if err != nil {
		log.Fatalf("Alice failed to send message 2: %v", err)
	}
	fmt.Println("✓ Alice sent message 2 while Bob was offline")

	// Reconnect Bob WebSocket
	if err := clientB.ConnectWS(); err != nil {
		log.Fatalf("Bob failed to reconnect WebSocket: %v", err)
	}
	fmt.Println("✓ Bob reconnected WebSocket connection (Simulated Network Recovery)")

	// Bob sends RECONNECT event to synchronize history since offline timestamp
	err = clientB.SendWS(&WSPacket{
		Type:               "RECONNECT",
		ReconnectTimestamp: timeBeforeOfflineMsg.Format(time.RFC3339),
		RoomID:             roomID,
	})
	if err != nil {
		log.Fatalf("Bob failed to send RECONNECT synchronization message: %v", err)
	}
	fmt.Println("✓ Bob sent RECONNECT replay event history query")

	// Verify Bob receives the missed message replayed by the server
	select {
	case p := <-clientB.MsgChan:
		if p.Type != "MESSAGE" || p.Message == nil || p.Message.ID != message2ID {
			log.Fatalf("FAIL: Bob did not receive replayed offline message 2 correctly: %+v", p)
		}
		if string(p.Message.EncryptedPayload) != msg2Payload {
			log.Fatalf("FAIL: Replayed message 2 has incorrect payload: %s", string(p.Message.EncryptedPayload))
		}
		fmt.Printf("✓ Bob recovered missed offline message: '%s' (Successful Synchronization)\n", string(p.Message.EncryptedPayload))
	case <-time.After(5 * time.Second):
		log.Fatalf("FAIL: Bob did not receive replayed offline message within timeout")
	}

	// ======================================================
	// Phase 8 — Security Validation
	// ======================================================
	fmt.Println("\n--- PHASE 8: Security Validation ---")

	// Try querying profiles directly without authorization
	respSec, err := http.Get(gatewayURL + "/api/v1/user/profile")
	if err != nil {
		log.Fatalf("Direct profile request HTTP error: %v", err)
	}
	respSec.Body.Close()
	if respSec.StatusCode != http.StatusUnauthorized {
		log.Fatalf("FAIL: Unauthorized request was not rejected with 401 (got %d)", respSec.StatusCode)
	}
	fmt.Println("✓ Unauthorized requests successfully rejected with HTTP 401")

	// Try querying profiles with an invalid token
	reqSec, _ := http.NewRequest("GET", gatewayURL+"/api/v1/user/profile", nil)
	reqSec.Header.Set("Authorization", "Bearer invalid_jwt_token_sample")
	respSec2, err := http.DefaultClient.Do(reqSec)
	if err != nil {
		log.Fatalf("Direct profile request HTTP error: %v", err)
	}
	respSec2.Body.Close()
	if respSec2.StatusCode != http.StatusUnauthorized {
		log.Fatalf("FAIL: Invalid JWT token request was not rejected with 401 (got %d)", respSec2.StatusCode)
	}
	fmt.Println("✓ Invalid token requests successfully rejected with HTTP 401")

	// Clean up resources
	clientA.DisconnectWS()
	clientB.DisconnectWS()

	// Clear DB records from run
	_, _ = db.Exec("DELETE FROM users WHERE device_id IN ('device_sim_a', 'device_sim_b')")

	fmt.Println("\n=================================================================")
	fmt.Println("ALL NINE PHASES OF INTEGRATION VALIDATION PASSED SUCCESSFULLY (100%)")
	fmt.Println("=================================================================")
}
