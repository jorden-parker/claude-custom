package catalog

import (
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"
)

var ensureNow = time.Date(2026, 10, 26, 12, 0, 0, 0, time.UTC)

const ensureMaxAge = 7 * 24 * time.Hour

func servedFixture(t *testing.T, status int, hits *atomic.Int32) *httptest.Server {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hits.Add(1)
		if status != http.StatusOK {
			w.WriteHeader(status)
			return
		}
		w.Write(readFixture(t))
	}))
	t.Cleanup(server.Close)
	return server
}

func saveOldSnapshot(t *testing.T, path string, syncedAt time.Time) {
	t.Helper()
	if err := SaveSnapshot(path, Snapshot{Source: "old", SyncedAt: syncedAt, Tools: []Tool{{Name: "Old"}}}); err != nil {
		t.Fatal(err)
	}
}

func TestEnsureKeepsFreshSnapshotWithoutFetching(t *testing.T) {
	path := filepath.Join(t.TempDir(), "tools.json")
	saveOldSnapshot(t, path, ensureNow.Add(-time.Hour))
	var hits atomic.Int32
	server := servedFixture(t, http.StatusOK, &hits)

	snapshot, err := Ensure(path, server.URL, ensureMaxAge, ensureNow)

	if err != nil || hits.Load() != 0 || snapshot.Source != "old" {
		t.Fatalf("got %+v, %v after %d fetches; want the fresh snapshot, no fetch", snapshot, err, hits.Load())
	}
}

func TestEnsureFetchesStaleSnapshot(t *testing.T) {
	path := filepath.Join(t.TempDir(), "tools.json")
	saveOldSnapshot(t, path, ensureNow.Add(-8*24*time.Hour))
	var hits atomic.Int32
	server := servedFixture(t, http.StatusOK, &hits)

	snapshot, err := Ensure(path, server.URL, ensureMaxAge, ensureNow)

	if err != nil || hits.Load() != 1 || snapshot.Source != server.URL || !snapshot.SyncedAt.Equal(ensureNow) {
		t.Fatalf("got %+v, %v after %d fetches; want a fresh fetch", snapshot, err, hits.Load())
	}
	stored, err := LoadSnapshot(path)
	if err != nil || len(stored.Tools) != len(snapshot.Tools) {
		t.Fatalf("stored = %+v, %v; want the fetched snapshot saved", stored, err)
	}
}

func TestEnsureFetchesMissingSnapshot(t *testing.T) {
	path := filepath.Join(t.TempDir(), "tools.json")
	var hits atomic.Int32
	server := servedFixture(t, http.StatusOK, &hits)

	snapshot, err := Ensure(path, server.URL, ensureMaxAge, ensureNow)

	if err != nil || hits.Load() != 1 || len(snapshot.Tools) == 0 {
		t.Fatalf("got %+v, %v after %d fetches; want a fetched snapshot", snapshot, err, hits.Load())
	}
}

func TestEnsureReturnsStaleSnapshotWhenFetchFails(t *testing.T) {
	path := filepath.Join(t.TempDir(), "tools.json")
	syncedAt := ensureNow.Add(-8 * 24 * time.Hour)
	saveOldSnapshot(t, path, syncedAt)
	var hits atomic.Int32
	server := servedFixture(t, http.StatusInternalServerError, &hits)

	snapshot, err := Ensure(path, server.URL, ensureMaxAge, ensureNow)

	if err != nil || hits.Load() != 1 || snapshot.Source != "old" || !snapshot.SyncedAt.Equal(syncedAt) {
		t.Fatalf("got %+v, %v after %d fetches; want the old snapshot without error", snapshot, err, hits.Load())
	}
}

func TestEnsureFailsWhenMissingAndFetchFails(t *testing.T) {
	path := filepath.Join(t.TempDir(), "tools.json")
	var hits atomic.Int32
	server := servedFixture(t, http.StatusInternalServerError, &hits)

	_, err := Ensure(path, server.URL, ensureMaxAge, ensureNow)

	if err == nil {
		t.Fatal("Ensure succeeded without a snapshot or a fetch")
	}
}
