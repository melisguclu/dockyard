import DockCore
import Foundation
import Testing

@testable import DockKit

@Suite("Layout benchmark", .disabled(if: ProcessInfo.processInfo.environment["DOCKYARD_BENCH"] == nil))
struct LayoutBenchmark {
    private func tiles(applications: Int, windows: Int) -> [DockTile] {
        var result: [DockTile] = []
        for index in 0..<applications {
            result.append(
                DockTile(
                    id: .bundle("com.example.app\(index)"),
                    kind: .application,
                    label: "App \(index)",
                    url: URL(fileURLWithPath: "/Applications/App\(index).app"),
                    bundleIdentifier: "com.example.app\(index)",
                    isRunning: index % 3 == 0,
                    isPinned: true
                )
            )
        }
        result.append(DockTile(id: .builtin(.separator), kind: .separator, label: ""))
        for index in 0..<windows {
            result.append(
                DockTile(
                    id: .window(UInt64(index)),
                    kind: .minimizedWindow,
                    label: "Window \(index)",
                    url: URL(fileURLWithPath: "/Applications/App0.app"),
                    bundleIdentifier: "com.example.app0"
                )
            )
        }
        result.append(DockTile(id: .builtin(.trash), kind: .trash(isEmpty: true), label: "Trash"))
        return result
    }

    private func measure(_ tiles: [DockTile], passes: Int = 20_000) -> (p50: Double, p99: Double) {
        let appearance = DockAppearance(
            tileSize: 30,
            largeSize: 48,
            magnificationEnabled: true
        )
        let panel = CGSize(width: 2560, height: 120)
        var samples: [Double] = []
        samples.reserveCapacity(passes)

        for pass in 0..<passes {
            let cursor = CGPoint(x: 200 + Double(pass % 1200), y: 40)
            let start = CFAbsoluteTimeGetCurrent()
            let layout = DockGeometry.layout(
                DockLayoutInput(
                    tiles: tiles,
                    appearance: appearance,
                    metrics: .current,
                    panelSize: panel,
                    cursor: cursor,
                    magnificationAmount: 1,
                    measuredEdgeMargin: nil
                )
            )
            samples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
            #expect(layout.tileFrames.count == tiles.count)
        }

        samples.sort()
        return (samples[passes / 2], samples[passes * 99 / 100])
    }

    @Test("Placing the hover label costs a fraction of a layout pass")
    func labelCost() {
        let tiles = tiles(applications: 23, windows: 8)
        let appearance = DockAppearance(tileSize: 30, largeSize: 48, magnificationEnabled: true)
        let panel = CGSize(width: 2560, height: 120)
        let layout = DockGeometry.layout(
            DockLayoutInput(
                tiles: tiles,
                appearance: appearance,
                metrics: .current,
                panelSize: panel,
                cursor: CGPoint(x: 900, y: 40),
                magnificationAmount: 1,
                measuredEdgeMargin: nil
            )
        )
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let passes = 20_000

        var placement: [Double] = []
        placement.reserveCapacity(passes)
        for pass in 0..<passes {
            let point = CGPoint(x: 200 + Double(pass % 1200), y: 40)
            let start = CFAbsoluteTimeGetCurrent()
            if let index = DockGeometry.hitIndex(in: layout, at: point), index < tiles.count {
                _ = DockTileLabelLayout.balloon(
                    width: 149,
                    anchor: layout.tileFrames[index],
                    orientation: .bottom,
                    screen: screen
                )
            }
            placement.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
        }

        var measurement: [Double] = []
        measurement.reserveCapacity(passes)
        for pass in 0..<passes {
            let title = "Application \(pass % 64)"
            let start = CFAbsoluteTimeGetCurrent()
            _ = DockTileLabelLayout.width(
                textWidth: DockTileLabelTextView.width(of: title, metrics: .current)
            )
            measurement.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
        }

        placement.sort()
        measurement.sort()
        print(String(format: "hit test + balloon, every frame   p50 %.4f ms  p99 %.4f ms",
                     placement[passes / 2], placement[passes * 99 / 100]))
        print(String(format: "text measurement, once per tile   p50 %.4f ms  p99 %.4f ms",
                     measurement[passes / 2], measurement[passes * 99 / 100]))
    }

    @Test("A bar with minimized windows lays out inside the frame budget")
    func layoutCost() {
        let before = measure(tiles(applications: 23, windows: 0))
        let after = measure(tiles(applications: 23, windows: 8))
        let stress = measure(tiles(applications: 23, windows: 40))

        print(String(format: "24 tiles  p50 %.4f ms  p99 %.4f ms", before.p50, before.p99))
        print(String(format: "32 tiles  p50 %.4f ms  p99 %.4f ms", after.p50, after.p99))
        print(String(format: "64 tiles  p50 %.4f ms  p99 %.4f ms", stress.p50, stress.p99))
    }
}
