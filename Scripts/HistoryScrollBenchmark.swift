import AppKit
import CodexWidgetKit
import SwiftUI
import Darwin

/// Controlled native scroll-event workload, not an FPS or trackpad-latency measurement.
/// Uses synthetic history and never initializes the account monitor.
@main
enum HistoryScrollBenchmark {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let samples: [UsageSample] = (0 ... 4_320).compactMap { index in
            guard !(2_000 ... 2_048).contains(index) else { return nil }
            let date = now.addingTimeInterval(Double(index - 4_320) * 600)
            let cycleIndex = index % 1_008
            return UsageSample(observedAt: date, remainingPercent: max(0, 100 - Double(cycleIndex / 12)), resetsAt: date.addingTimeInterval(Double(1_008 - cycleIndex) * 600))
        }
        let prepared = HistoryChartData(samples: samples, range: now.addingTimeInterval(-30 * 86_400) ... now, bucketDuration: 1_800)
        let view = HistoryChart(samples: samples, range: now.addingTimeInterval(-30 * 86_400) ... now, bucketDuration: 1_800, visibleDuration: 7 * 86_400, remainingPercent: 65)
            .padding(24).frame(width: 460)
            .background { UsageSurfaceBackground(remaining: 65) }
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 460, height: 280), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Scroll benchmark"
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            func scrollViews(_ view: NSView) -> [NSScrollView] {
                (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
            }
            let candidates = scrollViews(host)
            guard let scroll = candidates.first(where: { ($0.documentView?.bounds.width ?? 0) > $0.contentView.bounds.width + 100 }) else {
                fputs("No native horizontal scroll view; this benchmark needs updating for the current Charts implementation.\n", stderr)
                exit(1)
            }
            let maxX = scroll.documentView!.bounds.width - scroll.contentView.bounds.width
            guard maxX > 1_250 else {
                fputs("Benchmark viewport is too small for the expected sweep.\n", stderr)
                exit(1)
            }
            var intervals: [Double] = []
            var durations: [Double] = []
            let start = ProcessInfo.processInfo.systemUptime
            let cpuStart = cpuTime()
            var previous = start
            var steps = 0
            var positions: [Double] = []
            let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { timer in
                let tick = ProcessInfo.processInfo.systemUptime
                intervals.append((tick - previous) * 1_000)
                previous = tick
                // Precise events sweep backward then forward over 1,260 points.
                // Send directly to our own scroll view; no global input injection.
                let delta = steps < 180 ? 7 : -7
                let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: Int32(delta), wheel3: 0)!
                event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
                event.setIntegerValueField(.scrollWheelEventScrollPhase, value: steps == 0 ? 1 : (steps == 359 ? 4 : 2))
                scroll.scrollWheel(with: NSEvent(cgEvent: event)!)
                host.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                positions.append(scroll.contentView.bounds.minX)
                durations.append((ProcessInfo.processInfo.systemUptime - tick) * 1_000)
                steps += 1
                if steps == 360 {
                    timer.invalidate()
                    // Drain the final update before sampling total CPU.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        let elapsed = ProcessInfo.processInfo.systemUptime - start
                        let cpu = cpuTime() - cpuStart
                        let sorted = intervals.sorted()
                        let output: [String: Any] = [
                            "steps": steps, "wall_seconds": elapsed, "cpu_seconds": cpu,
                            "prepared_readings": prepared.series.runs.reduce(0) { $0 + $1.points.count },
                            "drawing_points": prepared.linePoints.count,
                            "cpu_ms_per_update": cpu * 1_000 / Double(steps),
                            "interval_median_ms": sorted[sorted.count / 2],
                            "interval_p95_ms": sorted[Int(Double(sorted.count - 1) * 0.95)],
                            "interval_over_16_67_ms": intervals.filter { $0 > 16.667 }.count,
                            "sync_update_ms": durations.reduce(0, +) / Double(steps),
                            "scroll_span_points": maxX,
                            "observed_span_points": positions.max()! - positions.min()!,
                            "os": ProcessInfo.processInfo.operatingSystemVersionString
                        ]
                        let json = try! JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
                        print("RESULT " + String(data: json, encoding: .utf8)!)
                        fflush(stdout)
                        app.terminate(nil)
                    }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
        }
        app.run()
    }

    static func cpuTime() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
}
