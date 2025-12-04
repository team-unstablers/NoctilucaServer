# DesktopContextManager debouncing notes
# Status: DONE — 150ms debounce + merge implemented in `AppSession.setupRefreshPipeline`/`enqueueRefresh`

Goal: avoid AX notification storms while not missing window changes in `AppSession.handleAXNotification`.

## Options

- Simple debounce (DispatchWorkItem)
  ```swift
  private var refreshWorkItem: DispatchWorkItem?
  private let refreshDelay: TimeInterval = 0.15

  private func scheduleRefresh() {
      refreshWorkItem?.cancel()
      let item = DispatchWorkItem { [weak self] in
          Task { try? await self?.refreshWindows() }
      }
      refreshWorkItem = item
      DispatchQueue.main.asyncAfter(deadline: .now() + refreshDelay, execute: item)
  }
  // call scheduleRefresh() inside handleAXNotification
  ```
  Pros: trivial, preserves event order via main queue. Cons: delay uses main queue; heavy main work can stall scheduling.

- Throttle with merge (single in-flight)
  ```swift
  private var isRefreshing = false
  private var pendingRefresh = false

  private func enqueueRefresh() {
      if isRefreshing {
          pendingRefresh = true
          return
      }
      isRefreshing = true
      Task.detached(priority: .utility) { [weak self] in
          defer { self?.isRefreshing = false }
          _ = try? await self?.refreshWindows()
          if self?.pendingRefresh == true {
              self?.pendingRefresh = false
              self?.enqueueRefresh()
          }
      }
  }
  ```
  Pros: collapses bursts to at most two runs. Cons: no time-based spacing unless you add a small delay.

- Time-slice throttle (interval guard)
  ```swift
  private var lastRefresh = Date.distantPast
  private let minInterval: TimeInterval = 0.1

  private func throttleRefresh() {
      let now = Date()
      if now.timeIntervalSince(lastRefresh) < minInterval { return }
      lastRefresh = now
      Task { try? await refreshWindows() }
  }
  ```
  Pros: hard cap on call frequency. Cons: may skip intermediate changes unless paired with a trailing run.

## Recommendation

- Use debounce 100–200ms plus merge for AX-heavy apps:
  - `handleAXNotification` → `scheduleRefresh()`.
  - Keep CGWindowList/AX fetch in a utility-priority Task (current implementation) so the main queue only schedules the debounce.
  - Expect ~6–10 refreshes per second during window drags, reducing CPU/network load.

## Cleanup & tuning

- Cancel `refreshWorkItem` when tearing down `AppSession` so pending callbacks do not hit deallocated delegates.
- Start with 150ms; tighten to 80–120ms if drag responsiveness matters, or relax to 150–200ms for lower overhead.
