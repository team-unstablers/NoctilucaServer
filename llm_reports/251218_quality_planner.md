# Quality Planner & Performance Reporting Integration (2025-12-18)

## Summary
- Implemented `AutoQualityPlanner` state machine to dynamically adjust target/max bitrate using multiplier and strategy-specific degradation steps (resolution/fps).
- Wired performance reports from client to server via `ProjectionChannel` and applied bitrate updates/backpressure feedback in `ProjectionSession`.
- Added client-side performance reporter (1s window) and decode-time measurement to feed `ProjectionPerformanceReport`.
- Added unit tests for `AutoQualityPlanner` in `NoctilucaServerTests`.

## Changes
- **AutoQualityPlanner** (`NoctilucaServer/feature/projection/encoder/quality/AutoQualityPlanner.swift`)
  - Multiplier (0.5~1.5) adjusts preset target/max bitrate; degradation steps vary by `AutoQualityStrategy`.
  - Inputs: `feed(report:)` (drop ratio, avg decode ms, EMA-smoothed) and `feed(backpressure:)` (EMA-smoothed 0/1 with threshold 0.5).
  - Scoring + cooldown: score ≥3 (≥4 critical) triggers degrade (multiplier 0.9 or 0.8, steps +1/+2); score ≤ -3 triggers recovery (multiplier ×1.02, step -1). Cooldown 3 ticks after each move; score reset after move.
  - Degrade thresholds: drop >5% (critical >15%), decode over budget (~70% of frame budget), or sustained backpressure (after smoothing) raise score. Recovery: stable windows (low drop & decode OK) lower score.
- **Backpressure aggregation in server** (`NoctilucaServer/feature/projection/ProjectionSession.swift`)
  - Frame-level backpressure is aggregated over ~0.5s (30 ticks @60fps). Only if ≥30% of the window sees backpressure, a single `feed(backpressure:)` is sent to the planner. Prevents per-frame overreaction.
- **Server projection pipeline**
  - `ProjectionChannel` handles `projectionPerformanceReport` and routes to session.
  - `ProjectionSession` creates planner, applies initial target/max bitrate, feeds backpressure (aggregated) and reports, updates encoder bitrates accordingly, and logs planned degradations (resolution/fps application pending).
- **Client performance reporting**
  - `ProjectionPerformanceReporter` (client `ProjectionSession`) aggregates per-second `(received, decoded, dropped, avg decode ms)` per session ID and sends `projectionPerformanceReport` via `ProjectionChannel`.
  - `VTVideoDecoder` measures per-frame decode time; `ProjectionSession` counts received/decoded/dropped frames.
- **Testing**
  - `NoctilucaServerTests/AutoQualityPlannerTests.swift` covers: initial preset, critical degradation (multi-tick), staged recovery with cooldown, backpressure streak triggering degrade.

## Assumptions / TODO
- Proto assumed: `ProjectionPerformanceReport` includes `identifier`, no `currentQueueSize`; actual proto/regenerated code may need alignment.
- Planned degradation steps (resolution/fps) are not yet applied to capture/encoder; tracked in issue https://github.com/team-unstablers/NoctilucaServer/issues/2.

## Verification
- Unit tests added; not executed here. Run `xcodebuild test -scheme NoctilucaServerTests` (or via Xcode) to validate.
