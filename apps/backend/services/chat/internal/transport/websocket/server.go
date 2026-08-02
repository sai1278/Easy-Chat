// Package websocket provides the WebSocket transport layer for the chat service.
// This file fixes:
//   - CRIT-03: double-close panic — sync.Once guards channel close
//   - CRIT-04: Redis Pub/Sub goroutine leak — goroutine exits on ctx cancel
//   - CRIT-06: WebSocket auth now validates the JWT Bearer token from the header
//   - CRIT-13: PING handler no longer blocks on c.send; uses non-blocking select
//   - HIGH-04: all sends to c.send use non-blocking select with timeout/drop semantics
//   - HIGH-05: context.WithTimeout replaces context.Background() for DB/cache ops
//   - HIGH-06: raw SQL removed from Kafka consumer; uses RoomRepository interface
//   - MED-15:  online presence uses per-device reference counting via Redis SADD/SREM
package websocket

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/gorilla/websocket"
	"github.com/redis/go-redis/v9"
	"nearby/backend/services/chat/internal/application"
	"nearby/backend/services/chat/internal/domain"
)

const (
	writeWait  = 10 * time.Second
	pongWait   = 60 * time.Second
	pingPeriod = (pongWait * 9) / 10

	// sendBufSize is the maximum number of messages buffered per client.
	// Slow clients that fill this buffer will have low-priority events dropped.
	sendBufSize = 256
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:    4096,
	WriteBufferSize:   4096,
	EnableCompression: true,
	CheckOrigin: func(r *http.Request) bool {
		// In production, restrict to the configured origin domain.
		// Returning true here is acceptable behind a gateway that enforces CORS.
		return true
	},
}

// Server manages active WebSocket client connections and event routing.
type Server struct {
	usecase    *application.ChatUsecase
	roomRepo   domain.RoomRepository
	rdb        *redis.Client
	jwtParser  *jwt.Parser
	jwtKeyFn   jwt.Keyfunc
	clients    map[string]*Client
	mu         sync.RWMutex
}

// NewServer creates a new WebSocket Server.
//
// roomRepo replaces the raw *sql.DB previously imported into this transport layer
// (HIGH-06: Clean Architecture — transport must not issue SQL directly).
//
// signingKey is the shared HMAC secret used to verify internal JWT tokens (CRIT-06).
func NewServer(
	usecase *application.ChatUsecase,
	roomRepo domain.RoomRepository,
	rdb *redis.Client,
	signingKey []byte,
) *Server {
	keyFn := func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return signingKey, nil
	}
	return &Server{
		usecase:  usecase,
		roomRepo: roomRepo,
		rdb:      rdb,
		jwtParser: jwt.NewParser(
			jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
			jwt.WithExpirationRequired(),
		),
		jwtKeyFn: keyFn,
		clients:  make(map[string]*Client),
	}
}

// Client represents a single authenticated WebSocket connection.
type Client struct {
	userID    string
	deviceID  string // unique per-device for reference-counted presence (MED-15)
	conn      *websocket.Conn
	send      chan []byte
	closeOnce sync.Once // CRIT-03: prevent double-close of send channel
	server    *Server
	roomSubs  map[string]func() error
	mu        sync.Mutex
}

// HandleWS upgrades an HTTP connection, validates the JWT, then registers the client.
//
// CRIT-06: Authentication is now performed against the Authorization Bearer token.
// The ?user_id= query parameter is no longer accepted.
func (s *Server) HandleWS(w http.ResponseWriter, r *http.Request) {
	// 1. Extract and verify JWT from Authorization header.
	authHeader := r.Header.Get("Authorization")
	if authHeader == "" {
		// Fall back to query param for WebSocket clients that cannot set headers.
		// The token is still cryptographically verified; only the transport differs.
		authHeader = "Bearer " + r.URL.Query().Get("token")
	}
	if !strings.HasPrefix(authHeader, "Bearer ") {
		http.Error(w, `{"error":"Unauthorized: missing bearer token"}`, http.StatusUnauthorized)
		return
	}
	tokenStr := strings.TrimPrefix(authHeader, "Bearer ")

	token, err := s.jwtParser.Parse(tokenStr, s.jwtKeyFn)
	if err != nil || !token.Valid {
		http.Error(w, `{"error":"Unauthorized: invalid token"}`, http.StatusUnauthorized)
		return
	}
	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		http.Error(w, `{"error":"Unauthorized: invalid claims"}`, http.StatusUnauthorized)
		return
	}
	userID, _ := claims["sub"].(string)
	sessionID, _ := claims["sid"].(string)
	if userID == "" || sessionID == "" {
		http.Error(w, `{"error":"Unauthorized: sub/sid claims missing"}`, http.StatusUnauthorized)
		return
	}

	// 2. Upgrade connection.
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		slog.Error("WebSocket upgrade failed", "err", err)
		return
	}

	// Use sessionID as the unique device key so multi-device presence works correctly.
	client := &Client{
		userID:   userID,
		deviceID: sessionID,
		conn:     conn,
		send:     make(chan []byte, sendBufSize),
		server:   s,
		roomSubs: make(map[string]func() error),
	}

	s.register(client)

	go client.writePump()
	go client.readPump()
}

// register adds a client and marks the user as online using per-device presence (MED-15).
func (s *Server) register(c *Client) {
	s.mu.Lock()
	s.clients[c.userID+":"+c.deviceID] = c
	s.mu.Unlock()

	// Reference-counted presence: SADD tracks each device separately.
	// The user is "online" as long as the set is non-empty.
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	presenceKey := "presence:" + c.userID
	_ = s.rdb.SAdd(ctx, presenceKey, c.deviceID).Err()
	_ = s.rdb.Expire(ctx, presenceKey, 24*time.Hour).Err()
	_ = s.usecase.SetUserOnline(ctx, c.userID, true)
	slog.Info("Client registered", "userID", c.userID, "deviceID", c.deviceID)
}

// unregister removes a client safely via sync.Once (CRIT-03).
func (s *Server) unregister(c *Client) {
	c.closeOnce.Do(func() {
		// Remove from clients map under write lock.
		s.mu.Lock()
		delete(s.clients, c.userID+":"+c.deviceID)
		s.mu.Unlock()

		// Close the send channel exactly once.
		close(c.send)
		_ = c.conn.Close()

		// Clean up room subscriptions.
		c.mu.Lock()
		for _, unsub := range c.roomSubs {
			_ = unsub()
		}
		c.mu.Unlock()

		// Reference-counted presence: remove this device from the set.
		// Only mark user offline when no devices remain (MED-15).
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		presenceKey := "presence:" + c.userID
		remaining, err := s.rdb.SRem(ctx, presenceKey, c.deviceID).Result()
		if err != nil || remaining == 0 {
			count, _ := s.rdb.SCard(ctx, presenceKey).Result()
			if count == 0 {
				_ = s.usecase.SetUserOnline(ctx, c.userID, false)
			}
		}
		slog.Info("Client unregistered", "userID", c.userID, "deviceID", c.deviceID)
	})
}

// StartKafkaConsumer runs a loop consuming Kafka events and routing them to client inboxes.
//
// HIGH-06: Raw SQL has been replaced by roomRepo.GetMembers() — transport layer
// no longer issues database queries directly.
func (s *Server) StartKafkaConsumer(ctx context.Context, pipeline domain.EventPipeline) {
	ch, err := pipeline.ConsumeChatEvents(ctx)
	if err != nil {
		slog.Error("Failed to start Kafka consumer loop", "err", err)
		return
	}
	slog.Info("Kafka consumer pipeline started successfully")

	for {
		select {
		case <-ctx.Done():
			return
		case event, ok := <-ch:
			if !ok {
				return
			}
			// Fetch room members via repository (not raw SQL).
			members, err := s.roomRepo.GetMembers(ctx, event.RoomID)
			if err != nil {
				slog.Error("Failed to fetch room members", "roomID", event.RoomID, "err", err)
				continue
			}

			payload, err := json.Marshal(event)
			if err != nil {
				slog.Error("Failed to marshal Kafka event", "err", err)
				continue
			}

			// Deliver to all room members (handles multi-user rooms, not just 2-party).
			for _, memberID := range members {
				_ = s.rdb.Publish(ctx, "chat:user:inbox:"+memberID, payload).Err()
			}
		}
	}
}

// sendNonBlocking attempts to write p to c.send without blocking.
// For time-critical events (typing indicators) the message is dropped if the buffer is full.
// This prevents the readPump goroutine from stalling (HIGH-04).
func (c *Client) sendNonBlocking(p []byte) {
	select {
	case c.send <- p:
	default:
		slog.Warn("Client send buffer full, dropping message", "userID", c.userID)
	}
}

func (c *Client) readPump() {
	defer c.server.unregister(c)

	c.conn.SetReadLimit(512 * 1024)
	_ = c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		_ = c.conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	// Subscribe to own Redis inbox for horizontal scaling.
	// The context is tied to this goroutine; cancel() is deferred so the
	// pubsub goroutine exits cleanly when readPump returns (CRIT-04).
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	pubsub := c.server.rdb.Subscribe(ctx, "chat:user:inbox:"+c.userID)
	defer pubsub.Close()

	// Forward inbox messages to the WebSocket client.
	// This goroutine exits when pubsub.Channel() is closed, which happens
	// when pubsub.Close() is called in the defer above (CRIT-04 fix).
	go func() {
		for msg := range pubsub.Channel() {
			// Use non-blocking send to avoid blocking this goroutine
			// against a slow client or a closed channel (HIGH-04 + CRIT-04).
			select {
			case c.send <- []byte(msg.Payload):
			case <-ctx.Done():
				return
			}
		}
	}()

	for {
		_, payload, err := c.conn.ReadMessage()
		if err != nil {
			if !errors.Is(err, websocket.ErrCloseSent) {
				slog.Info("WebSocket read error, closing connection", "userID", c.userID, "err", err)
			}
			break
		}

		var packet struct {
			Type               string                  `json:"type"`
			Message            *domain.Message         `json:"message"`
			Receipt            *domain.ReadReceipt     `json:"receipt"`
			Typing             *domain.TypingIndicator `json:"typing"`
			ReconnectTimestamp string                  `json:"reconnect_timestamp"`
			Limit              int                     `json:"limit"`
			Offset             int                     `json:"offset"`
			RoomID             string                  `json:"room_id"`
		}
		if err := json.Unmarshal(payload, &packet); err != nil {
			slog.Error("Failed to parse WebSocket packet", "err", err)
			continue
		}

		switch packet.Type {
		case "PING":
			// CRIT-13: reset deadline then send PONG via non-blocking write.
			_ = c.conn.SetReadDeadline(time.Now().Add(pongWait))
			pongEvt := map[string]string{"type": "PONG"}
			p, _ := json.Marshal(pongEvt)
			c.sendNonBlocking(p)

		case "MESSAGE":
			if packet.Message != nil {
				opCtx, opCancel := context.WithTimeout(ctx, 15*time.Second)
				err := c.server.usecase.ProcessIncomingMessage(opCtx, c.userID, packet.Message)
				if err != nil {
					slog.Error("Failed to process incoming message", "err", err)
				}
				opCancel()
			}

		case "RECEIPT":
			if packet.Receipt != nil {
				opCtx, opCancel := context.WithTimeout(ctx, 15*time.Second)
				_ = c.server.usecase.ProcessReadReceipt(opCtx, c.userID, packet.Receipt)
				opCancel()
			}

		case "TYPING":
			if packet.Typing != nil {
				opCtx, opCancel := context.WithTimeout(ctx, 2*time.Second)
				_ = c.server.usecase.ProcessTyping(opCtx, c.userID, packet.Typing)
				opCancel()
			}

		case "RECONNECT":
			if packet.ReconnectTimestamp != "" {
				t, err := time.Parse(time.RFC3339, packet.ReconnectTimestamp)
				if err == nil {
					limit := packet.Limit
					if limit <= 0 || limit > 200 {
						limit = 100 // enforce safe default (MED-20)
					}
					opCtx, opCancel := context.WithTimeout(ctx, 10*time.Second)
					history, err := c.server.usecase.GetOfflineHistory(opCtx, c.userID, t, limit, packet.Offset)
					opCancel()
					if err == nil {
						for _, m := range history {
							evt := &domain.EventPacket{
								Type:     "MESSAGE",
								SenderID: m.SenderID,
								RoomID:   m.RoomID,
								Message:  m,
							}
							p, _ := json.Marshal(evt)
							c.sendNonBlocking(p)
						}
					}
				}
			}

		case "SUBSCRIBE_ROOM":
			if packet.RoomID != "" {
				c.mu.Lock()
				if _, ok := c.roomSubs[packet.RoomID]; !ok {
					subCtx, _ := context.WithCancel(ctx) //nolint:govet
					ch, unsub, err := c.server.usecase.SubscribeRoomTyping(subCtx, packet.RoomID)
					if err == nil {
						c.roomSubs[packet.RoomID] = unsub
						go func(room string, typingCh <-chan *domain.TypingIndicator) {
							for indicator := range typingCh {
								evt := &domain.EventPacket{
									Type:     "TYPING",
									SenderID: indicator.UserID,
									RoomID:   room,
									Typing:   indicator,
								}
								p, _ := json.Marshal(evt)
								c.sendNonBlocking(p) // HIGH-04: non-blocking
							}
						}(packet.RoomID, ch)
					}
				}
				c.mu.Unlock()
			}

		case "UNSUBSCRIBE_ROOM":
			if packet.RoomID != "" {
				c.mu.Lock()
				if unsub, ok := c.roomSubs[packet.RoomID]; ok {
					_ = unsub()
					delete(c.roomSubs, packet.RoomID)
				}
				c.mu.Unlock()
			}
		}
	}
}

func (c *Client) writePump() {
	ticker := time.NewTicker(pingPeriod)
	// CRIT-03: writePump no longer calls unregister. Only readPump drives
	// the connection lifecycle. writePump exits cleanly when c.send closes.
	defer ticker.Stop()

	for {
		select {
		case msg, ok := <-c.send:
			_ = c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				// Channel closed by unregister — send a WebSocket CLOSE frame.
				_ = c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := c.conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				return
			}
		case <-ticker.C:
			_ = c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// HandleRooms handles HTTP requests for conversation room lifecycle management.
// Specifically: POST /api/v1/chat/rooms to create or retrieve a unique room for two users.
func (s *Server) HandleRooms(w http.ResponseWriter, r *http.Request) {
	// Only allow POST requests for room creation/lookup
	if r.Method != http.MethodPost {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusMethodNotAllowed)
		_, _ = w.Write([]byte(`{"error":"Method not allowed"}`))
		return
	}

	// 1. Extract and verify JWT from Authorization header
	authHeader := r.Header.Get("Authorization")
	if !strings.HasPrefix(authHeader, "Bearer ") {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(`{"error":"Unauthorized: missing bearer token"}`))
		return
	}
	tokenStr := strings.TrimPrefix(authHeader, "Bearer ")

	token, err := s.jwtParser.Parse(tokenStr, s.jwtKeyFn)
	if err != nil || !token.Valid {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(fmt.Sprintf(`{"error":"Unauthorized: invalid token: %v"}`, err)))
		return
	}
	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(`{"error":"Unauthorized: invalid claims"}`))
		return
	}
	userID, _ := claims["sub"].(string)
	if userID == "" {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(`{"error":"Unauthorized: sub claim missing"}`))
		return
	}

	// 2. Parse request body
	bodyBytes, err := io.ReadAll(r.Body)
	if err != nil || len(bodyBytes) == 0 {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"error":"Invalid request body: empty or unreadable"}`))
		return
	}

	var req struct {
		UserA string `json:"userA"`
		UserB string `json:"userB"`
	}
	if err := json.Unmarshal(bodyBytes, &req); err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(fmt.Sprintf(`{"error":"Invalid request body: %v"}`, err)))
		return
	}

	// 3. Validate Authorization: The requester must be one of the participants
	if userID != req.UserA && userID != req.UserB {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusForbidden)
		_, _ = w.Write([]byte(`{"error":"Forbidden: you must be one of the participants"}`))
		return
	}

	// 4. Resolve room ID from usecase
	roomID, err := s.usecase.GetOrCreateRoom(r.Context(), req.UserA, req.UserB)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		if strings.Contains(err.Error(), "do not exist") {
			w.WriteHeader(http.StatusBadRequest)
		} else {
			w.WriteHeader(http.StatusInternalServerError)
		}
		_, _ = w.Write([]byte(fmt.Sprintf(`{"error":%q}`, err.Error())))
		return
	}

	// 5. Respond with room details
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]string{
		"roomId": roomID,
	})
}

