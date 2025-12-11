package main

import (
	"encoding/gob"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func resetOverviewSnapshotForTest() {
	overviewSnapshotMu.Lock()
	overviewSnapshotCache = nil
	overviewSnapshotLoaded = false
	overviewSnapshotMu.Unlock()
}

func TestScanPathConcurrentBasic(t *testing.T) {
	root := t.TempDir()

	rootFile := filepath.Join(root, "root.txt")
	if err := os.WriteFile(rootFile, []byte("root-data"), 0o644); err != nil {
		t.Fatalf("write root file: %v", err)
	}

	nested := filepath.Join(root, "nested")
	if err := os.MkdirAll(nested, 0o755); err != nil {
		t.Fatalf("create nested dir: %v", err)
	}

	fileOne := filepath.Join(nested, "a.bin")
	if err := os.WriteFile(fileOne, []byte("alpha"), 0o644); err != nil {
		t.Fatalf("write file one: %v", err)
	}
	fileTwo := filepath.Join(nested, "b.bin")
	if err := os.WriteFile(fileTwo, []byte(strings.Repeat("b", 32)), 0o644); err != nil {
		t.Fatalf("write file two: %v", err)
	}

	linkPath := filepath.Join(root, "link-to-a")
	if err := os.Symlink(fileOne, linkPath); err != nil {
		t.Fatalf("create symlink: %v", err)
	}

	var filesScanned, dirsScanned, bytesScanned int64
	current := ""

	result, err := scanPathConcurrent(root, &filesScanned, &dirsScanned, &bytesScanned, &current)
	if err != nil {
		t.Fatalf("scanPathConcurrent returned error: %v", err)
	}

	linkInfo, err := os.Lstat(linkPath)
	if err != nil {
		t.Fatalf("stat symlink: %v", err)
	}

	expectedDirSize := int64(len("alpha") + len(strings.Repeat("b", 32)))
	expectedRootFileSize := int64(len("root-data"))
	expectedLinkSize := getActualFileSize(linkPath, linkInfo)
	expectedTotal := expectedDirSize + expectedRootFileSize + expectedLinkSize

	if result.TotalSize != expectedTotal {
		t.Fatalf("expected total size %d, got %d", expectedTotal, result.TotalSize)
	}

	if got := atomic.LoadInt64(&filesScanned); got != 3 {
		t.Fatalf("expected 3 files scanned, got %d", got)
	}
	if dirs := atomic.LoadInt64(&dirsScanned); dirs == 0 {
		t.Fatalf("expected directory scan count to increase")
	}
	if bytes := atomic.LoadInt64(&bytesScanned); bytes == 0 {
		t.Fatalf("expected byte counter to increase")
	}
	if current == "" {
		t.Fatalf("expected current path to be updated")
	}

	foundSymlink := false
	for _, entry := range result.Entries {
		if strings.HasSuffix(entry.Name, " →") {
			foundSymlink = true
			if entry.IsDir {
				t.Fatalf("symlink entry should not be marked as directory")
			}
		}
	}
	if !foundSymlink {
		t.Fatalf("expected symlink entry to be present in scan result")
	}
}

func TestDeletePathWithProgress(t *testing.T) {
	parent := t.TempDir()
	target := filepath.Join(parent, "target")
	if err := os.MkdirAll(target, 0o755); err != nil {
		t.Fatalf("create target: %v", err)
	}

	files := []string{
		filepath.Join(target, "one.txt"),
		filepath.Join(target, "two.txt"),
	}
	for _, f := range files {
		if err := os.WriteFile(f, []byte("content"), 0o644); err != nil {
			t.Fatalf("write %s: %v", f, err)
		}
	}

	var counter int64
	count, err := deletePathWithProgress(target, &counter)
	if err != nil {
		t.Fatalf("deletePathWithProgress returned error: %v", err)
	}
	if count != int64(len(files)) {
		t.Fatalf("expected %d files removed, got %d", len(files), count)
	}
	if got := atomic.LoadInt64(&counter); got != count {
		t.Fatalf("counter mismatch: want %d, got %d", count, got)
	}
	if _, err := os.Stat(target); !os.IsNotExist(err) {
		t.Fatalf("expected target to be removed, stat err=%v", err)
	}
}

func TestOverviewStoreAndLoad(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	resetOverviewSnapshotForTest()
	t.Cleanup(resetOverviewSnapshotForTest)

	path := filepath.Join(home, "project")
	want := int64(123456)

	if err := storeOverviewSize(path, want); err != nil {
		t.Fatalf("storeOverviewSize: %v", err)
	}

	got, err := loadStoredOverviewSize(path)
	if err != nil {
		t.Fatalf("loadStoredOverviewSize: %v", err)
	}
	if got != want {
		t.Fatalf("snapshot mismatch: want %d, got %d", want, got)
	}

	// Force reload from disk and ensure value persists.
	resetOverviewSnapshotForTest()
	got, err = loadStoredOverviewSize(path)
	if err != nil {
		t.Fatalf("loadStoredOverviewSize after reset: %v", err)
	}
	if got != want {
		t.Fatalf("snapshot mismatch after reset: want %d, got %d", want, got)
	}
}

func TestCacheSaveLoadRoundTrip(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	target := filepath.Join(home, "cache-target")
	if err := os.MkdirAll(target, 0o755); err != nil {
		t.Fatalf("create target dir: %v", err)
	}

	result := scanResult{
		Entries: []dirEntry{
			{Name: "alpha", Path: filepath.Join(target, "alpha"), Size: 10, IsDir: true},
		},
		LargeFiles: []fileEntry{
			{Name: "big.bin", Path: filepath.Join(target, "big.bin"), Size: 2048},
		},
		TotalSize: 42,
	}

	if err := saveCacheToDisk(target, result); err != nil {
		t.Fatalf("saveCacheToDisk: %v", err)
	}

	cache, err := loadCacheFromDisk(target)
	if err != nil {
		t.Fatalf("loadCacheFromDisk: %v", err)
	}
	if cache.TotalSize != result.TotalSize {
		t.Fatalf("total size mismatch: want %d, got %d", result.TotalSize, cache.TotalSize)
	}
	if len(cache.Entries) != len(result.Entries) {
		t.Fatalf("entry count mismatch: want %d, got %d", len(result.Entries), len(cache.Entries))
	}
	if len(cache.LargeFiles) != len(result.LargeFiles) {
		t.Fatalf("large file count mismatch: want %d, got %d", len(result.LargeFiles), len(cache.LargeFiles))
	}
}

func TestMeasureOverviewSize(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	resetOverviewSnapshotForTest()
	t.Cleanup(resetOverviewSnapshotForTest)

	target := filepath.Join(home, "measure")
	if err := os.MkdirAll(target, 0o755); err != nil {
		t.Fatalf("create target: %v", err)
	}
	content := []byte(strings.Repeat("x", 2048))
	if err := os.WriteFile(filepath.Join(target, "data.bin"), content, 0o644); err != nil {
		t.Fatalf("write file: %v", err)
	}

	size, err := measureOverviewSize(target)
	if err != nil {
		t.Fatalf("measureOverviewSize: %v", err)
	}
	if size <= 0 {
		t.Fatalf("expected positive size, got %d", size)
	}

	// Ensure snapshot stored
	cached, err := loadStoredOverviewSize(target)
	if err != nil {
		t.Fatalf("loadStoredOverviewSize: %v", err)
	}
	if cached != size {
		t.Fatalf("snapshot mismatch: want %d, got %d", size, cached)
	}
}

func TestIsCleanableDir(t *testing.T) {
	if !isCleanableDir("/Users/test/project/node_modules") {
		t.Fatalf("expected node_modules to be cleanable")
	}
	if isCleanableDir("/Users/test/Library/Caches/AppCache") {
		t.Fatalf("Library caches should be handled by mo clean")
	}
	if isCleanableDir("") {
		t.Fatalf("empty path should not be cleanable")
	}
}

func TestHasUsefulVolumeMounts(t *testing.T) {
	root := t.TempDir()
	if hasUsefulVolumeMounts(root) {
		t.Fatalf("empty directory should not report useful mounts")
	}

	hidden := filepath.Join(root, ".hidden")
	if err := os.Mkdir(hidden, 0o755); err != nil {
		t.Fatalf("create hidden dir: %v", err)
	}
	if hasUsefulVolumeMounts(root) {
		t.Fatalf("hidden entries should not count as useful mounts")
	}

	mount := filepath.Join(root, "ExternalDrive")
	if err := os.Mkdir(mount, 0o755); err != nil {
		t.Fatalf("create mount dir: %v", err)
	}
	if !hasUsefulVolumeMounts(root) {
		t.Fatalf("expected useful mount when real directory exists")
	}
}

func TestLoadCacheExpiresWhenDirectoryChanges(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	target := filepath.Join(home, "change-target")
	if err := os.MkdirAll(target, 0o755); err != nil {
		t.Fatalf("create target: %v", err)
	}

	result := scanResult{TotalSize: 5}
	if err := saveCacheToDisk(target, result); err != nil {
		t.Fatalf("saveCacheToDisk: %v", err)
	}

	// Touch directory to advance mtime beyond grace period.
	time.Sleep(time.Millisecond * 10)
	if err := os.Chtimes(target, time.Now(), time.Now()); err != nil {
		t.Fatalf("chtimes: %v", err)
	}

	// Force modtime difference beyond grace window by simulating an older cache entry.
	cachePath, err := getCachePath(target)
	if err != nil {
		t.Fatalf("getCachePath: %v", err)
	}
	if _, err := os.Stat(cachePath); err != nil {
		t.Fatalf("stat cache: %v", err)
	}
	oldTime := time.Now().Add(-cacheModTimeGrace - time.Minute)
	if err := os.Chtimes(cachePath, oldTime, oldTime); err != nil {
		t.Fatalf("chtimes cache: %v", err)
	}

	file, err := os.Open(cachePath)
	if err != nil {
		t.Fatalf("open cache: %v", err)
	}
	var entry cacheEntry
	if err := gob.NewDecoder(file).Decode(&entry); err != nil {
		t.Fatalf("decode cache: %v", err)
	}
	_ = file.Close()

	entry.ScanTime = time.Now().Add(-8 * 24 * time.Hour)

	tmp := cachePath + ".tmp"
	f, err := os.Create(tmp)
	if err != nil {
		t.Fatalf("create tmp cache: %v", err)
	}
	if err := gob.NewEncoder(f).Encode(&entry); err != nil {
		t.Fatalf("encode tmp cache: %v", err)
	}
	_ = f.Close()
	if err := os.Rename(tmp, cachePath); err != nil {
		t.Fatalf("rename tmp cache: %v", err)
	}

	if _, err := loadCacheFromDisk(target); err == nil {
		t.Fatalf("expected cache load to fail after stale scan time")
	}
}

func TestScanPathPermissionError(t *testing.T) {
	root := t.TempDir()
	lockedDir := filepath.Join(root, "locked")
	if err := os.Mkdir(lockedDir, 0o755); err != nil {
		t.Fatalf("create locked dir: %v", err)
	}

	// Create a file inside before locking, just to be sure
	if err := os.WriteFile(filepath.Join(lockedDir, "secret.txt"), []byte("shh"), 0o644); err != nil {
		t.Fatalf("write secret: %v", err)
	}

	// Remove permissions
	if err := os.Chmod(lockedDir, 0o000); err != nil {
		t.Fatalf("chmod 000: %v", err)
	}
	defer func() {
		// Restore permissions so cleanup can work
		_ = os.Chmod(lockedDir, 0o755)
	}()

	var files, dirs, bytes int64
	current := ""

	// Scanning the locked dir itself should fail
	_, err := scanPathConcurrent(lockedDir, &files, &dirs, &bytes, &current)
	if err == nil {
		t.Fatalf("expected error scanning locked directory, got nil")
	}
	if !os.IsPermission(err) {
		t.Logf("unexpected error type: %v", err)
	}
}
