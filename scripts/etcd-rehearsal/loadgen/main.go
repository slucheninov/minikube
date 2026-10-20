// Command loadgen mimics the prod clients of the coredns etcd during the upgrade rehearsal:
//   - put:   corenet agent-k8s, plain Put of SkyDNS records under /skydns (no lease);
//   - get:   corenet metrics loop, prefix Get of the whole /skydns tree;
//   - lock:  processing-core, one concurrency.Session (TTL 10s) per lock + Mutex;
//   - lease: shared-lock-api, short lease (TTL 2s) renewed with KeepAliveOnce every second.
//
// Every operation has a timeout. A run of failures of one kind is an outage: it starts at the
// last success before the first failure and ends at the next success. GET /stats returns the
// counters and outages since start or the last POST /reset, so a step can be measured as
// reset -> action -> stats.
package main

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"go.etcd.io/etcd/api/v3/v3rpc/rpctypes"
	"go.etcd.io/etcd/client/pkg/v3/transport"
	clientv3 "go.etcd.io/etcd/client/v3"
	"go.etcd.io/etcd/client/v3/concurrency"
)

type outage struct {
	Op       string    `json:"op"`
	Worker   int       `json:"worker"`
	Start    time.Time `json:"start"`
	Seconds  float64   `json:"seconds"`
	Failures int       `json:"failures"`
	LastErr  string    `json:"last_error"`
}

type opStats struct {
	OK         int64   `json:"ok"`
	Err        int64   `json:"err"`
	MaxLatency float64 `json:"max_latency_s"`
	MaxOutage  float64 `json:"max_outage_s"`
	Lost       int64   `json:"lost,omitempty"` // lock: session expired, lease: lease expired
}

type workerState struct {
	lastOK   time.Time
	failures int
	lastErr  string
}

type recorder struct {
	mu      sync.Mutex
	since   time.Time
	ops     map[string]*opStats
	open    map[string]*workerState
	outages []outage
}

func newRecorder() *recorder {
	r := &recorder{}
	r.reset()
	return r
}

func (r *recorder) reset() {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.since = time.Now()
	r.ops = map[string]*opStats{}
	r.outages = nil
	// Keep open outages but restart them at the reset moment so they are counted in the new window.
	if r.open == nil {
		r.open = map[string]*workerState{}
	}
	for _, w := range r.open {
		if w.failures > 0 {
			w.lastOK = r.since
		}
	}
}

func (r *recorder) stat(op string) *opStats {
	s, ok := r.ops[op]
	if !ok {
		s = &opStats{}
		r.ops[op] = s
	}
	return s
}

func (r *recorder) record(op string, worker int, start time.Time, err error) {
	now := time.Now()
	r.mu.Lock()
	defer r.mu.Unlock()
	s := r.stat(op)
	key := fmt.Sprintf("%s/%d", op, worker)
	w, ok := r.open[key]
	if !ok {
		w = &workerState{lastOK: now}
		r.open[key] = w
	}
	if lat := now.Sub(start).Seconds(); lat > s.MaxLatency {
		s.MaxLatency = lat
	}
	if err != nil {
		s.Err++
		w.failures++
		w.lastErr = err.Error()
		if w.failures == 1 {
			log.Printf("ERROR op=%s worker=%d err=%v", op, worker, err)
		}
		return
	}
	s.OK++
	if w.failures > 0 {
		o := outage{Op: op, Worker: worker, Start: w.lastOK, Seconds: now.Sub(w.lastOK).Seconds(), Failures: w.failures, LastErr: w.lastErr}
		r.outages = append(r.outages, o)
		if o.Seconds > s.MaxOutage {
			s.MaxOutage = o.Seconds
		}
		log.Printf("OUTAGE op=%s worker=%d seconds=%.2f failures=%d last_error=%q", op, worker, o.Seconds, o.Failures, o.LastErr)
	}
	w.failures = 0
	w.lastOK = now
}

func (r *recorder) lost(op string, worker int, why string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.stat(op).Lost++
	log.Printf("LOST op=%s worker=%d %s", op, worker, why)
}

func (r *recorder) snapshot() map[string]any {
	r.mu.Lock()
	defer r.mu.Unlock()
	now := time.Now()
	ops := map[string]opStats{}
	for k, v := range r.ops {
		ops[k] = *v
	}
	var ongoing []outage
	for key, w := range r.open {
		if w.failures > 0 {
			op, _, _ := strings.Cut(key, "/")
			ongoing = append(ongoing, outage{Op: op, Start: w.lastOK, Seconds: now.Sub(w.lastOK).Seconds(), Failures: w.failures, LastErr: w.lastErr})
		}
	}
	return map[string]any{"since": r.since, "seconds": now.Sub(r.since).Seconds(), "ops": ops, "outages": r.outages, "ongoing": ongoing}
}

func env(name, def string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return def
}

func main() {
	endpoints := flag.String("endpoints", env("ETCD_ENDPOINTS", "https://etcd.coredns.svc.cluster.local:2379"), "comma separated etcd endpoints")
	certDir := flag.String("cert-dir", env("ETCD_CERT_DIR", "/etc/etcd/certs"), "directory with ca.crt, tls.crt, tls.key")
	prefix := flag.String("prefix", env("SKYDNS_PREFIX", "/skydns/local/cluster/rehearsal"), "key prefix for SkyDNS records")
	readPrefix := flag.String("read-prefix", "/skydns", "prefix read by the get loop")
	lockers := flag.Int("lockers", 4, "lock workers (session per lock)")
	lockTTL := flag.Int("lock-ttl", 10, "lock session TTL, seconds")
	leases := flag.Int("leases", 4, "short lease workers")
	leaseTTL := flag.Int64("lease-ttl", 2, "short lease TTL, seconds")
	interval := flag.Duration("interval", 200*time.Millisecond, "put interval")
	opTimeout := flag.Duration("op-timeout", 2*time.Second, "per operation timeout")
	listen := flag.String("listen", ":8080", "stats HTTP listener")
	flag.Parse()

	tlsInfo := transport.TLSInfo{
		CertFile:      *certDir + "/tls.crt",
		KeyFile:       *certDir + "/tls.key",
		TrustedCAFile: *certDir + "/ca.crt",
	}
	tlsConfig, err := tlsInfo.ClientConfig()
	if err != nil {
		log.Fatalf("tls: %v", err)
	}
	tlsConfig.MinVersion = tls.VersionTLS12
	// Same as the prod clients: no AutoSyncInterval, library default keepalives.
	cli, err := clientv3.New(clientv3.Config{
		Endpoints:   strings.Split(*endpoints, ","),
		DialTimeout: 5 * time.Second,
		TLS:         tlsConfig,
	})
	if err != nil {
		log.Fatalf("client: %v", err)
	}
	defer cli.Close()

	rec := newRecorder()
	ctx := context.Background()

	go putLoop(ctx, cli, rec, *prefix, *interval, *opTimeout)
	go getLoop(ctx, cli, rec, *readPrefix, *opTimeout)
	for i := 0; i < *lockers; i++ {
		go lockLoop(ctx, cli, rec, i, *lockTTL, *opTimeout)
	}
	for i := 0; i < *leases; i++ {
		go leaseLoop(ctx, cli, rec, i, *leaseTTL, *opTimeout)
	}
	go func() {
		for range time.Tick(10 * time.Second) {
			b, _ := json.Marshal(rec.snapshot()["ops"])
			log.Printf("STATS %s", b)
		}
	}()

	http.HandleFunc("/stats", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(rec.snapshot())
	})
	http.HandleFunc("/reset", func(w http.ResponseWriter, req *http.Request) {
		if req.Method != http.MethodPost {
			http.Error(w, "POST only", http.StatusMethodNotAllowed)
			return
		}
		rec.reset()
		w.WriteHeader(http.StatusNoContent)
	})
	log.Printf("loadgen endpoints=%s lockers=%d leases=%d", *endpoints, *lockers, *leases)
	log.Fatal(http.ListenAndServe(*listen, nil))
}

func putLoop(ctx context.Context, cli *clientv3.Client, rec *recorder, prefix string, interval, timeout time.Duration) {
	for n := 0; ; n++ {
		start := time.Now()
		key := fmt.Sprintf("%s/pod-%d", prefix, n%50)
		val := fmt.Sprintf(`{"host":"10.250.%d.%d","priority":10,"ttl":10}`, n%50/250, n%250)
		c, cancel := context.WithTimeout(ctx, timeout)
		_, err := cli.Put(c, key, val)
		cancel()
		rec.record("put", 0, start, err)
		time.Sleep(time.Until(start.Add(interval)))
	}
}

func getLoop(ctx context.Context, cli *clientv3.Client, rec *recorder, prefix string, timeout time.Duration) {
	for {
		start := time.Now()
		c, cancel := context.WithTimeout(ctx, timeout)
		_, err := cli.Get(c, prefix, clientv3.WithPrefix(), clientv3.WithKeysOnly())
		cancel()
		rec.record("get", 0, start, err)
		time.Sleep(time.Until(start.Add(time.Second)))
	}
}

// lockLoop takes and releases one lock in a loop. A session is reused until it expires,
// as a long running worker would do. Lost sessions are counted separately.
func lockLoop(ctx context.Context, cli *clientv3.Client, rec *recorder, id, ttl int, timeout time.Duration) {
	key := fmt.Sprintf("/rehearsal/locks/lock-%d", id)
	var session *concurrency.Session
	for {
		start := time.Now()
		if session == nil {
			// The session keepalive runs on this context, so it must not carry a deadline:
			// the timer only bounds the lease grant.
			c, cancel := context.WithCancel(ctx)
			timer := time.AfterFunc(timeout, cancel)
			s, err := concurrency.NewSession(cli, concurrency.WithTTL(ttl), concurrency.WithContext(c))
			if !timer.Stop() && err == nil {
				err = context.DeadlineExceeded
				_ = s.Close()
			}
			if err != nil {
				cancel()
				rec.record("lock", id, start, fmt.Errorf("session: %w", err))
				time.Sleep(500 * time.Millisecond)
				continue
			}
			go func() { <-s.Done(); cancel() }()
			session = s
		}
		select {
		case <-session.Done():
			rec.lost("lock", id, "session expired")
			session = nil
			continue
		default:
		}
		m := concurrency.NewMutex(session, key)
		c, cancel := context.WithTimeout(ctx, timeout)
		err := m.Lock(c)
		cancel()
		if err != nil {
			rec.record("lock", id, start, err)
			time.Sleep(200 * time.Millisecond)
			continue
		}
		time.Sleep(300 * time.Millisecond)
		c, cancel = context.WithTimeout(ctx, timeout)
		err = m.Unlock(c)
		cancel()
		rec.record("lock", id, start, err)
		time.Sleep(200 * time.Millisecond)
	}
}

// leaseLoop holds a short lease and renews it with one KeepAliveOnce per second,
// like shared-lock-api on each caller /keepalive. An expired lease is "lost" and regranted.
func leaseLoop(ctx context.Context, cli *clientv3.Client, rec *recorder, id int, ttl int64, timeout time.Duration) {
	key := fmt.Sprintf("/rehearsal/leases/lease-%d", id)
	var lease clientv3.LeaseID
	for {
		start := time.Now()
		c, cancel := context.WithTimeout(ctx, timeout)
		var err error
		if lease == 0 {
			var g *clientv3.LeaseGrantResponse
			if g, err = cli.Grant(c, ttl); err == nil {
				if _, err = cli.Put(c, key, "held", clientv3.WithLease(g.ID)); err == nil {
					lease = g.ID
				}
			}
		} else {
			_, err = cli.KeepAliveOnce(c, lease)
			if errors.Is(err, rpctypes.ErrLeaseNotFound) {
				rec.lost("lease", id, fmt.Sprintf("lease %x expired", lease))
				lease = 0
			}
		}
		cancel()
		rec.record("lease", id, start, err)
		time.Sleep(time.Until(start.Add(time.Second)))
	}
}
