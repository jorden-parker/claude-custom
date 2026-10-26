package catalog

import "time"

func Ensure(snapshotPath, url string, maxAge time.Duration, now time.Time) (Snapshot, error) {
	cached, loadErr := LoadSnapshot(snapshotPath)
	if loadErr == nil && now.Sub(cached.SyncedAt) <= maxAge {
		return cached, nil
	}
	fetched, err := fetchSnapshot(snapshotPath, url, now)
	if err == nil {
		return fetched, nil
	}
	if loadErr == nil {
		return cached, nil
	}
	return Snapshot{}, err
}

func fetchSnapshot(snapshotPath, url string, now time.Time) (Snapshot, error) {
	tools, err := Fetch(url)
	if err != nil {
		return Snapshot{}, err
	}
	snapshot := Snapshot{Source: url, SyncedAt: now, Tools: tools}
	return snapshot, SaveSnapshot(snapshotPath, snapshot)
}
