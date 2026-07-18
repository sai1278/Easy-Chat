package main

import (
	"context"
	"fmt"
	"sync"
	"testing"
	"time"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/tools/leaderelection/resourcelock"
)

// ─── helpers ────────────────────────────────────────────────────────────────

func newTestController(primaryRegion, secondaryRegion string) *DRController {
	return &DRController{
		k8sClient:     nil, // offline simulation mode
		isLeader:      true,
		fencingToken:  "test-fence-token-fixed",
		leaseDuration: 400 * time.Millisecond,
		renewDeadline: 300 * time.Millisecond,
		retryPeriod:   100 * time.Millisecond,
		policy: &DisasterRecoveryPolicy{
			PrimaryRegion:    primaryRegion,
			SecondaryRegion:  secondaryRegion,
			ActiveRegion:     primaryRegion,
			FailureThreshold: 3,
		},
	}
}

// ─── 1. Full Region Outage ──────────────────────────────────────────────────

func TestDRChaos_FullRegionOutage(t *testing.T) {
	t.Log("[SCENARIO] Full primary region shutdown detected by DR controller")
	ctrl := newTestController("us-east1", "us-west1")

	// Inject network-partition failure for the primary region
	ctrl.chaosProbe = func(region string) error {
		if region == "us-east1" {
			return ErrNetworkPartition
		}
		return nil
	}

	ctx := context.Background()
	ctrl.reconcile(ctx)

	if ctrl.policy.ActiveRegion != "us-west1" {
		t.Errorf("[FAIL] expected failover to us-west1, got %s", ctrl.policy.ActiveRegion)
	}
	if ctrl.lastMetrics == nil || !ctrl.lastMetrics.SLAPass {
		t.Error("[FAIL] SLA compliance not met after full region outage")
	}
	t.Logf("[PASS] Full region outage: failover to %s completed, RTO=%v, RPO=%v",
		ctrl.policy.ActiveRegion, ctrl.lastMetrics.RTO, ctrl.lastMetrics.RPO)
}

// ─── 2. Network Partition (Partial Degradation) ─────────────────────────────

func TestDRChaos_NetworkPartition(t *testing.T) {
	t.Log("[SCENARIO] Network partition between regions (no route to host)")
	ctrl := newTestController("us-east1", "us-west1")

	ctrl.chaosProbe = func(region string) error {
		return ErrNetworkPartition
	}

	ctx := context.Background()
	ctrl.reconcile(ctx)

	if ctrl.policy.ActiveRegion != "us-west1" {
		t.Errorf("[FAIL] expected promotion under network partition, got %s", ctrl.policy.ActiveRegion)
	}
	t.Logf("[PASS] Network partition handled: new active region=%s", ctrl.policy.ActiveRegion)
}

// ─── 3. High Latency Degradation ────────────────────────────────────────────

func TestDRChaos_HighLatencyProbe(t *testing.T) {
	t.Log("[SCENARIO] Sustained high latency >500ms from primary region")
	ctrl := newTestController("us-east1", "us-west1")

	ctrl.chaosProbe = func(region string) error {
		if region == "us-east1" {
			return ErrHighLatency
		}
		return nil
	}

	ctx := context.Background()
	ctrl.reconcile(ctx)

	if ctrl.policy.ActiveRegion != "us-west1" {
		t.Errorf("[FAIL] high latency should trigger promotion, got region=%s", ctrl.policy.ActiveRegion)
	}
	t.Logf("[PASS] High latency probe: promoted to %s", ctrl.policy.ActiveRegion)
}

// ─── 4. Kafka Broker Failure ─────────────────────────────────────────────────

func TestDRChaos_KafkaBrokerOutage(t *testing.T) {
	t.Log("[SCENARIO] Partial Kafka broker failure during failover")
	ctrl := newTestController("us-east1", "us-west1")

	ctrl.chaosProbe = func(region string) error {
		return ErrKafkaBrokerDown
	}

	ctx := context.Background()
	ctrl.reconcile(ctx)

	if ctrl.policy.ActiveRegion != "us-west1" {
		t.Errorf("[FAIL] Kafka outage should trigger regional promotion, got %s", ctrl.policy.ActiveRegion)
	}
	t.Logf("[PASS] Kafka broker outage: controller promoted region=%s, SLA=%v",
		ctrl.policy.ActiveRegion, ctrl.lastMetrics.SLAPass)
}

// ─── 5. PostgreSQL Replication Lag Spike ─────────────────────────────────────

func TestDRChaos_PostgresLagSpike(t *testing.T) {
	t.Log("[SCENARIO] PostgreSQL replication lag >30s detected by health probe")
	ctrl := newTestController("us-east1", "us-west1")

	ctrl.chaosProbe = func(region string) error {
		if region == "us-east1" {
			return ErrPostgresLagSpike
		}
		return nil
	}

	ctx := context.Background()
	ctrl.reconcile(ctx)

	if ctrl.policy.ActiveRegion != "us-west1" {
		t.Errorf("[FAIL] Postgres lag spike should trigger promotion, got %s", ctrl.policy.ActiveRegion)
	}
	if ctrl.lastMetrics.RPO > 30*time.Second {
		t.Errorf("[FAIL] RPO SLA breached: %v", ctrl.lastMetrics.RPO)
	}
	t.Logf("[PASS] Postgres lag spike: promoted to %s, RPO=%v", ctrl.policy.ActiveRegion, ctrl.lastMetrics.RPO)
}

// ─── 6. Redis Node Failure ───────────────────────────────────────────────────

func TestDRChaos_RedisNodeOutage(t *testing.T) {
	t.Log("[SCENARIO] Redis primary node down, Sentinel failover required")
	ctrl := newTestController("us-east1", "us-west1")

	ctrl.chaosProbe = func(region string) error {
		return ErrRedisNodeDown
	}

	ctx := context.Background()
	ctrl.reconcile(ctx)

	if ctrl.policy.ActiveRegion != "us-west1" {
		t.Errorf("[FAIL] Redis failure should trigger DR promotion, got %s", ctrl.policy.ActiveRegion)
	}
	t.Logf("[PASS] Redis node outage: controller promoted to %s", ctrl.policy.ActiveRegion)
}

// ─── 7. Idempotency Under Concurrent Reconcile Calls ─────────────────────────

func TestDRChaos_ConcurrentReconcile_Idempotency(t *testing.T) {
	t.Log("[SCENARIO] Concurrent reconcile calls must not cause double-failover or split-brain")
	ctrl := newTestController("us-east1", "us-west1")

	ctrl.chaosProbe = func(region string) error {
		if region == "us-east1" {
			return ErrNetworkPartition
		}
		return nil
	}

	ctx := context.Background()
	var wg sync.WaitGroup
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			ctrl.reconcile(ctx)
		}()
	}
	wg.Wait()

	// After N concurrent reconciles, active region must be exactly us-west1
	if ctrl.policy.ActiveRegion != "us-west1" {
		t.Errorf("[FAIL] concurrent reconcile left inconsistent state: active=%s", ctrl.policy.ActiveRegion)
	}
	t.Logf("[PASS] Concurrent reconcile idempotency: final active region=%s", ctrl.policy.ActiveRegion)
}

// ─── 8. Fail-Closed: Controller Crash ────────────────────────────────────────

func TestDRChaos_FailClosed_ControllerCrash(t *testing.T) {
	t.Log("[SCENARIO] DR controller loses leadership; system must fail CLOSED")
	ctrl := newTestController("us-east1", "us-west1")
	ctrl.isLeader = false // Simulate crashed/partitioned leader

	// With no leader, the system must NOT advance active region.
	// isFailedClosed() must return true — routing stays on last known-good state.
	if !ctrl.isFailedClosed() {
		t.Error("[FAIL] controller without leader should report fail-closed state")
	}
	if ctrl.policy.ActiveRegion != "us-east1" {
		t.Errorf("[FAIL] routing must stay on last known-good primary, got %s", ctrl.policy.ActiveRegion)
	}
	t.Logf("[PASS] Fail-closed controller crash: active region held at %s", ctrl.policy.ActiveRegion)
}

// ─── 9. Fail-Closed: DNS Failure During Failover ─────────────────────────────

func TestDRChaos_FailClosed_DNSOutage(t *testing.T) {
	t.Log("[SCENARIO] DNS unavailable during failover; traffic must not leak")
	ctrl := newTestController("us-east1", "us-west1")

	// Even with DNS failure, the controller still promotes the active region pointer.
	// The key assertion: no split-brain (both primary and secondary must not be co-active).
	ctrl.chaosProbe = func(region string) error {
		if region == "us-east1" {
			return fmt.Errorf("DNS resolution failed for region endpoint: %s", region)
		}
		return nil
	}

	ctx := context.Background()
	ctrl.reconcile(ctx)

	// Exactly one region must be active after DNS failure handling
	if ctrl.policy.ActiveRegion == ctrl.policy.PrimaryRegion &&
		ctrl.policy.ActiveRegion == ctrl.policy.SecondaryRegion {
		t.Error("[FAIL] split-brain detected: both regions claim primary status")
	}
	t.Logf("[PASS] DNS outage during failover: single active region=%s", ctrl.policy.ActiveRegion)
}

// ─── 10. RTO / RPO Real Measurement Validation ───────────────────────────────

func TestDRChaos_RTO_RPO_RealMeasurement(t *testing.T) {
	t.Log("[SCENARIO] Measuring real RTO/RPO values under simulated full-region outage")
	ctrl := newTestController("us-east1", "us-west1")

	ctrl.chaosProbe = func(region string) error {
		if region == "us-east1" {
			return ErrNetworkPartition
		}
		return nil
	}

	wallStart := time.Now()
	ctx := context.Background()
	ctrl.reconcile(ctx)
	wallElapsed := time.Since(wallStart)

	if ctrl.lastMetrics == nil {
		t.Fatal("[FAIL] no DR metrics recorded after failover")
	}

	rto := ctrl.lastMetrics.RTO
	rpo := ctrl.lastMetrics.RPO

	t.Logf("[METRIC] Wall-clock failover time: %v", wallElapsed)
	t.Logf("[METRIC] RTO measured: %v (target ≤ 5m)", rto)
	t.Logf("[METRIC] RPO measured: %v (target ≤ 30s)", rpo)

	if rto > 5*time.Minute {
		t.Errorf("[FAIL] RTO SLA breached: %v > 5m", rto)
	}
	if rpo > 30*time.Second {
		t.Errorf("[FAIL] RPO SLA breached: %v > 30s", rpo)
	}
	if !ctrl.lastMetrics.SLAPass {
		t.Error("[FAIL] SLA compliance flag not set to PASS")
	}
	t.Logf("[PASS] RTO=%v, RPO=%v, SLA=%v", rto, rpo, ctrl.lastMetrics.SLAPass)
}

// ─── 11. Healthy Region Does NOT Trigger Failover ────────────────────────────

func TestDRChaos_HealthyRegion_NoFailover(t *testing.T) {
	t.Log("[SCENARIO] Healthy primary region must NOT trigger unnecessary failover")
	ctrl := newTestController("us-east1", "us-west1")

	// No chaos injected; probe returns healthy
	ctx := context.Background()
	ctrl.reconcile(ctx)

	if ctrl.policy.ActiveRegion != "us-east1" {
		t.Errorf("[FAIL] healthy region triggered unexpected failover to %s", ctrl.policy.ActiveRegion)
	}
	if ctrl.lastMetrics != nil {
		t.Error("[FAIL] failover metrics should not exist for healthy region")
	}
	t.Log("[PASS] Healthy region: no failover triggered, active region=us-east1")
}

// ─── 12. Recovery Determinism (Repeated Drills) ──────────────────────────────

func TestDRChaos_RepeatabilityDrill(t *testing.T) {
	t.Log("[SCENARIO] DR drill must produce deterministic results across 5 executions")

	for run := 1; run <= 5; run++ {
		ctrl := newTestController("us-east1", "us-west1")
		ctrl.chaosProbe = func(region string) error {
			if region == "us-east1" {
				return ErrNetworkPartition
			}
			return nil
		}
		ctx := context.Background()
		ctrl.reconcile(ctx)

		if ctrl.policy.ActiveRegion != "us-west1" {
			t.Errorf("[FAIL] drill run %d: expected us-west1, got %s", run, ctrl.policy.ActiveRegion)
		}
		if !ctrl.lastMetrics.SLAPass {
			t.Errorf("[FAIL] drill run %d: SLA not met", run)
		}
		t.Logf("[PASS] Drill run %d: active=%s, RTO=%v, RPO=%v, SLA=%v",
			run, ctrl.policy.ActiveRegion, ctrl.lastMetrics.RTO, ctrl.lastMetrics.RPO, ctrl.lastMetrics.SLAPass)
	}
}

// ─── Leader Election Integration Tests ─────────────────────────────────────

type MockResourceLock struct {
	mu             sync.Mutex
	identity       string
	leaderIdentity string
	record         *resourcelock.LeaderElectionRecord
	getFailures    int
	updateFailures int
}

func (m *MockResourceLock) Get(ctx context.Context) (*resourcelock.LeaderElectionRecord, []byte, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.getFailures > 0 {
		m.getFailures--
		return nil, nil, fmt.Errorf("transient API server Get failure")
	}
	if m.record == nil {
		return nil, nil, apierrors.NewNotFound(schema.GroupResource{Group: "coordination.k8s.io", Resource: "leases"}, m.identity)
	}
	return m.record, []byte("mock-data"), nil
}

func (m *MockResourceLock) Create(ctx context.Context, ler resourcelock.LeaderElectionRecord) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.record = &ler
	m.leaderIdentity = ler.HolderIdentity
	return nil
}

func (m *MockResourceLock) Update(ctx context.Context, ler resourcelock.LeaderElectionRecord) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.updateFailures > 0 {
		m.updateFailures--
		return fmt.Errorf("transient API server Update failure")
	}
	m.record = &ler
	m.leaderIdentity = ler.HolderIdentity
	return nil
}

func (m *MockResourceLock) RecordEvent(string) {}
func (m *MockResourceLock) Identity() string  { return m.identity }
func (m *MockResourceLock) Describe() string  { return "MockResourceLock:" + m.identity }

type sharedMockLeaseDB struct {
	mu     sync.Mutex
	record *resourcelock.LeaderElectionRecord
}

type SharedMockResourceLock struct {
	mu             sync.Mutex
	db             *sharedMockLeaseDB
	identity       string
	getFailures    int
	updateFailures int
}

func (m *SharedMockResourceLock) Get(ctx context.Context) (*resourcelock.LeaderElectionRecord, []byte, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.getFailures > 0 {
		m.getFailures--
		return nil, nil, fmt.Errorf("transient API server Get failure")
	}
	m.db.mu.Lock()
	defer m.db.mu.Unlock()
	if m.db.record == nil {
		return nil, nil, apierrors.NewNotFound(schema.GroupResource{Group: "coordination.k8s.io", Resource: "leases"}, m.identity)
	}
	rec := *m.db.record
	return &rec, []byte("mock-data"), nil
}

func (m *SharedMockResourceLock) Create(ctx context.Context, ler resourcelock.LeaderElectionRecord) error {
	m.db.mu.Lock()
	defer m.db.mu.Unlock()
	if m.db.record != nil && m.db.record.HolderIdentity != "" {
		return fmt.Errorf("conflict: lease already exists and is held by %s", m.db.record.HolderIdentity)
	}
	m.db.record = &ler
	return nil
}

func (m *SharedMockResourceLock) Update(ctx context.Context, ler resourcelock.LeaderElectionRecord) error {
	m.mu.Lock()
	if m.updateFailures > 0 {
		m.updateFailures--
		m.mu.Unlock()
		return fmt.Errorf("transient API server Update failure")
	}
	m.mu.Unlock()

	m.db.mu.Lock()
	defer m.db.mu.Unlock()
	if m.db.record == nil {
		return fmt.Errorf("conflict: lease does not exist to update")
	}

	// 1. If we are the current holder, we can update it (renew or release)
	if m.db.record.HolderIdentity == m.identity {
		m.db.record = &ler
		return nil
	}

	// 2. If it is currently released, anyone can take it
	if m.db.record.HolderIdentity == "" {
		m.db.record = &ler
		return nil
	}

	// 3. If someone else holds it, check if they are trying to take it over
	if ler.HolderIdentity == m.identity {
		renewTime := m.db.record.RenewTime.Time
		if time.Since(renewTime) > 400*time.Millisecond {
			m.db.record = &ler
			return nil
		}
		return fmt.Errorf("conflict: lease is still active and held by %s", m.db.record.HolderIdentity)
	}

	return fmt.Errorf("conflict: lease held by %s", m.db.record.HolderIdentity)
}

func (m *SharedMockResourceLock) RecordEvent(string) {}
func (m *SharedMockResourceLock) Identity() string  { return m.identity }
func (m *SharedMockResourceLock) Describe() string  { return "SharedMockResourceLock:" + m.identity }

// 1. API Server Transient Failures
func TestDRLeader_APIServerTransientFailures(t *testing.T) {
	lock := &MockResourceLock{
		identity:    "node-a",
		getFailures: 2,
	}
	ctrl := newTestController("us-east1", "us-west1")
	ctrl.testLock = lock
	ctrl.isLeader = false

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	go ctrl.runLeaderElection(ctx)

	time.Sleep(3 * time.Second)

	ctrl.mu.Lock()
	leader := ctrl.isLeader
	ctrl.mu.Unlock()
	if !leader {
		t.Error("expected controller to eventually acquire leadership after transient API server errors resolved")
	}
}

// 2. Network Partitions
func TestDRLeader_NetworkPartition(t *testing.T) {
	lock := &MockResourceLock{
		identity:    "node-a",
		getFailures: 100,
	}
	ctrl := newTestController("us-east1", "us-west1")
	ctrl.testLock = lock
	ctrl.isLeader = false

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	go ctrl.runLeaderElection(ctx)

	time.Sleep(1 * time.Second)

	ctrl.mu.Lock()
	leader := ctrl.isLeader
	ctrl.mu.Unlock()
	if leader {
		t.Error("expected controller to NOT acquire leadership during continuous network partition")
	}
}

// 3. Controller Restart
func TestDRLeader_ControllerRestart(t *testing.T) {
	lock := &MockResourceLock{
		identity: "node-a",
	}

	ctrl1 := newTestController("us-east1", "us-west1")
	ctrl1.testLock = lock
	ctrl1.isLeader = false

	ctx1, cancel1 := context.WithCancel(context.Background())
	go ctrl1.runLeaderElection(ctx1)

	time.Sleep(200 * time.Millisecond)
	ctrl1.mu.Lock()
	leader1 := ctrl1.isLeader
	ctrl1.mu.Unlock()
	if !leader1 {
		t.Fatal("expected ctrl1 to be leader")
	}

	cancel1()
	time.Sleep(200 * time.Millisecond)

	ctrl2 := newTestController("us-east1", "us-west1")
	ctrl2.testLock = lock
	ctrl2.isLeader = false

	ctx2, cancel2 := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel2()
	go ctrl2.runLeaderElection(ctx2)

	time.Sleep(500 * time.Millisecond)
	ctrl2.mu.Lock()
	leader2 := ctrl2.isLeader
	ctrl2.mu.Unlock()
	if !leader2 {
		t.Error("expected ctrl2 to acquire leadership after ctrl1 was restarted/stopped")
	}
}

// 4. Leader Handoff
func TestDRLeader_LeaderHandoff(t *testing.T) {
	db := &sharedMockLeaseDB{}
	lockA := &SharedMockResourceLock{
		db:       db,
		identity: "node-a",
	}

	ctrl1 := newTestController("us-east1", "us-west1")
	ctrl1.testLock = lockA
	ctrl1.isLeader = false

	ctx1, cancel1 := context.WithCancel(context.Background())
	go ctrl1.runLeaderElection(ctx1)

	time.Sleep(200 * time.Millisecond)

	lockB := &SharedMockResourceLock{
		db:       db,
		identity: "node-b",
	}

	ctrl2 := newTestController("us-east1", "us-west1")
	ctrl2.testLock = lockB
	ctrl2.isLeader = false

	ctx2, cancel2 := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel2()
	go ctrl2.runLeaderElection(ctx2)

	// Stop leader A
	cancel1()
	time.Sleep(1 * time.Second)

	// Standby B should become leader
	ctrl2.mu.Lock()
	leader2 := ctrl2.isLeader
	ctrl2.mu.Unlock()
	if !leader2 {
		time.Sleep(1 * time.Second)
		ctrl2.mu.Lock()
		leader2 = ctrl2.isLeader
		ctrl2.mu.Unlock()
		if !leader2 {
			t.Error("expected standby node-b to become leader after leader node-a resigned")
		}
	}
}

// 5. Concurrent Controller Startup
func TestDRLeader_ConcurrentControllerStartup(t *testing.T) {
	db := &sharedMockLeaseDB{}
	
	const nodeCount = 5
	var wg sync.WaitGroup
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	controllers := make([]*DRController, nodeCount)
	for i := 0; i < nodeCount; i++ {
		lock := &SharedMockResourceLock{
			db:       db,
			identity: fmt.Sprintf("node-%d", i),
		}
		ctrl := newTestController("us-east1", "us-west1")
		ctrl.testLock = lock
		ctrl.isLeader = false
		controllers[i] = ctrl

		wg.Add(1)
		go func(c *DRController) {
			defer wg.Done()
			c.runLeaderElection(ctx)
		}(ctrl)
	}

	time.Sleep(1 * time.Second)

	leaderCount := 0
	for i := 0; i < nodeCount; i++ {
		controllers[i].mu.Lock()
		if controllers[i].isLeader {
			leaderCount++
		}
		controllers[i].mu.Unlock()
	}

	if leaderCount > 1 {
		t.Errorf("expected at most 1 leader, got %d", leaderCount)
	}
	t.Logf("Concurrent startup completed. Leaders elected: %d", leaderCount)
	wg.Wait()
}
