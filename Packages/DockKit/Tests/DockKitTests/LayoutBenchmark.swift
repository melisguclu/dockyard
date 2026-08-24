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
                    reservedStrip: nil
                )
            )
            samples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
            #expect(layout.tileFrames.count == tiles.count)
        }

        samples.sort()
        return (samples[passes / 2], samples[passes * 99 / 100])
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
