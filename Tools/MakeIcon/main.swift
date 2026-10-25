import AppKit
import SwiftUI

// Renders Resources/AppIcon.icns from the companion drawing.
// Built and run by build.sh when the icon is missing; compiled together with Sources/ (minus main.swift).

struct AppIconView: View {
    var body: some View {
        // macOS icon grid: an 824pt rounded square centred on a 1024pt canvas.
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.09)], startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 46)
                .frame(width: 620, height: 620)
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(TimerModel.Mode.focus.accent, style: StrokeStyle(lineWidth: 46, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 620, height: 620)
            CompanionCanvas(mood: .cheerful, buddy: .mochi, time: 0.25)
                .frame(width: 560, height: 560)
                .offset(y: -70)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor
func writePNG(points: Int, scale: Int, to url: URL) throws {
    let renderer = ImageRenderer(content: AppIconView().scaleEffect(CGFloat(points) / 1024).frame(width: CGFloat(points), height: CGFloat(points)))
    renderer.scale = CGFloat(scale)
    guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    try data?.write(to: url)
}

MainActor.assumeIsolated {
    let output = URL(fileURLWithPath: CommandLine.arguments[1])
    let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
    try? FileManager.default.removeItem(at: iconset)
    try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        try! writePNG(points: points, scale: 1, to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
        try! writePNG(points: points, scale: 2, to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
    }
    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
    try! iconutil.run()
    iconutil.waitUntilExit()
    exit(iconutil.terminationStatus)
}
