import AppKit

// One 1024-point drawing supplies the app icon, transparent mark, and template.
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
  NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
func saved(_ draw: () -> Void) {
  NSGraphicsContext.saveGraphicsState()
  draw()
  NSGraphicsContext.restoreGraphicsState()
}
func placed(_ x: CGFloat, _ y: CGFloat, _ angle: CGFloat, _ draw: () -> Void) {
  saved {
    let t = NSAffineTransform()
    t.translateX(by: x, yBy: y)
    t.rotate(byDegrees: angle)
    t.concat()
    draw()
  }
}
func frontPage() -> NSBezierPath {
  let p = NSBezierPath()
  p.move(to: NSPoint(x: -152, y: -250))
  p.line(to: NSPoint(x: 152, y: -250))
  p.curve(to: NSPoint(x: 234, y: -168), controlPoint1: NSPoint(x: 197, y: -250), controlPoint2: NSPoint(x: 234, y: -213))
  p.line(to: NSPoint(x: 234, y: 101))
  p.curve(to: NSPoint(x: 223, y: 130), controlPoint1: NSPoint(x: 234, y: 113), controlPoint2: NSPoint(x: 230, y: 122))
  p.line(to: NSPoint(x: 113, y: 239))
  p.curve(to: NSPoint(x: 85, y: 250), controlPoint1: NSPoint(x: 105, y: 247), controlPoint2: NSPoint(x: 97, y: 250))
  p.line(to: NSPoint(x: -152, y: 250))
  p.curve(to: NSPoint(x: -234, y: 168), controlPoint1: NSPoint(x: -197, y: 250), controlPoint2: NSPoint(x: -234, y: 213))
  p.line(to: NSPoint(x: -234, y: -168))
  p.curve(to: NSPoint(x: -152, y: -250), controlPoint1: NSPoint(x: -234, y: -213), controlPoint2: NSPoint(x: -197, y: -250))
  p.close()
  return p
}
func foldedCorner() -> NSBezierPath {
  let p = NSBezierPath()
  p.move(to: NSPoint(x: 85, y: 250))
  p.curve(to: NSPoint(x: 90, y: 231), controlPoint1: NSPoint(x: 91, y: 246), controlPoint2: NSPoint(x: 91, y: 240))
  p.line(to: NSPoint(x: 88, y: 153))
  p.curve(to: NSPoint(x: 123, y: 117), controlPoint1: NSPoint(x: 87, y: 132), controlPoint2: NSPoint(x: 99, y: 120))
  p.line(to: NSPoint(x: 214, y: 106))
  p.curve(to: NSPoint(x: 234, y: 101), controlPoint1: NSPoint(x: 225, y: 105), controlPoint2: NSPoint(x: 231, y: 103))
  p.curve(to: NSPoint(x: 223, y: 130), controlPoint1: NSPoint(x: 234, y: 113), controlPoint2: NSPoint(x: 230, y: 122))
  p.line(to: NSPoint(x: 113, y: 239))
  p.curve(to: NSPoint(x: 85, y: 250), controlPoint1: NSPoint(x: 105, y: 247), controlPoint2: NSPoint(x: 97, y: 250))
  p.close()
  return p
}
func rearPage() -> NSBezierPath {
  NSBezierPath(roundedRect: NSRect(x: -189, y: -223, width: 378, height: 446), xRadius: 76, yRadius: 76)
}
func shadowed(_ path: NSBezierPath, fill: NSColor, opacity: CGFloat, blur: CGFloat, offset: CGFloat) {
  saved {
    let s = NSShadow()
    s.shadowColor = color(0.025, 0.27, 0.22, opacity)
    s.shadowOffset = NSSize(width: 0, height: offset)
    s.shadowBlurRadius = blur
    s.set()
    fill.setFill()
    path.fill()
  }
}
func drawPages(mark: Bool) {
  placed(432, 570, 13) {
    let rear = rearPage()
    shadowed(rear, fill: color(0.04, 0.48, 0.43), opacity: mark ? 0.15 : 0.20, blur: mark ? 12 : 20, offset: -10)
    NSGradient(starting: color(0.06, 0.57, 0.50), ending: color(0.025, 0.43, 0.39))!.draw(in: rear, angle: -70)
    color(0.035, 0.40, 0.36, 0.62).setStroke()
    rear.lineWidth = 2.5
    rear.stroke()
    let inset = NSBezierPath(roundedRect: NSRect(x: -185, y: -219, width: 370, height: 438), xRadius: 72, yRadius: 72)
    color(0.39, 0.82, 0.71, 0.22).setStroke()
    inset.lineWidth = 2
    inset.stroke()
  }
  placed(571, 450, -6.5) {
    let front = frontPage()
    shadowed(front, fill: color(0.99, 0.98, 0.95), opacity: mark ? 0.20 : 0.24, blur: mark ? 13 : 24, offset: -13)
    NSGradient(starting: color(1, 0.991, 0.968), ending: color(0.973, 0.965, 0.935))!.draw(in: front, angle: -80)
    // This edge remains visible against a pale title bar.
    color(0.46, 0.57, 0.51, mark ? 0.58 : 0.22).setStroke()
    front.lineWidth = mark ? 4.5 : 2
    front.stroke()
    let fold = foldedCorner()
    saved {
      front.addClip()
      shadowed(fold, fill: color(1, 0.48, 0.38), opacity: 0.15, blur: 7, offset: -4)
    }
    NSGradient(starting: color(1, 0.58, 0.47), ending: color(1, 0.43, 0.34))!.draw(in: fold, angle: -55)
    color(1, 0.77, 0.64, 0.60).setStroke()
    fold.lineWidth = 1.6
    fold.stroke()
  }
}
func drawAppIcon() {
  let base = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 222, yRadius: 222)
  shadowed(base, fill: color(0.78, 0.93, 0.87), opacity: 0.15, blur: 15, offset: -7)
  NSGradient(starting: color(0.88, 0.98, 0.94), ending: color(0.73, 0.90, 0.83))!.draw(in: base, angle: -80)
  color(0.43, 0.69, 0.60, 0.24).setStroke()
  base.lineWidth = 2
  base.stroke()
  let highlight = NSBezierPath(roundedRect: NSRect(x: 84, y: 84, width: 856, height: 856), xRadius: 218, yRadius: 218)
  color(1, 1, 1, 0.40).setStroke()
  highlight.lineWidth = 2
  highlight.stroke()
  drawPages(mark: false)
}
func fitStandalonePages(_ draw: () -> Void) {
  saved {
    let t = NSAffineTransform()
    t.translateX(by: 512, yBy: 512)
    t.scale(by: 1.34)
    t.translateX(by: -515, yBy: -503)
    t.concat()
    draw()
  }
}
func drawMenuTemplate() {
  fitStandalonePages {
    NSColor.black.setFill()
    placed(432, 570, 13) { rearPage().fill() }
    placed(571, 450, -6.5) {
      let front = frontPage()
      // Alpha cuts out the hollow sheet and separates it from the solid rear.
      saved {
        NSGraphicsContext.current!.cgContext.setBlendMode(.clear)
        front.fill()
        front.lineWidth = 122
        front.lineJoinStyle = .round
        front.stroke()
      }
      NSColor.black.setStroke()
      front.lineWidth = 76
      front.lineJoinStyle = .round
      front.stroke()
    }
  }
}
func render(size: Int, draw: () -> Void) -> Data {
  // Supersample small assets to preserve their curved edges and alpha.
  let renderSize = max(size, 256)
  let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: renderSize, pixelsHigh: renderSize,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: renderSize * 4, bitsPerPixel: 32)!
  saved {
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current!.imageInterpolation = .high
    let t = NSAffineTransform()
    t.scale(by: CGFloat(renderSize) / 1024)
    t.concat()
    draw()
  }
  if size == renderSize { return bitmap.representation(using: .png, properties: [:])! }
  let output = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
  saved {
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: output)
    NSGraphicsContext.current!.imageInterpolation = .high
    let image = NSImage(size: NSSize(width: renderSize, height: renderSize))
    image.addRepresentation(bitmap)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
  }
  return output.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count >= 2 else {
  fputs("Usage: swift scripts/make-icon.swift ICONSET_DIR [RESOURCES_DIR]\n", stderr)
  exit(1)
}
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
  let data = render(size: size, draw: drawAppIcon)
  let name = size == 1024 ? "icon_512x512@2x.png" : "icon_\(size)x\(size).png"
  try data.write(to: destination.appendingPathComponent(name))
  if [32, 64, 256, 512].contains(size) {
    try data.write(to: destination.appendingPathComponent("icon_\(size / 2)x\(size / 2)@2x.png"))
  }
}
if CommandLine.arguments.count >= 3 {
  let resources = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
  try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
  for (name, size) in [("QingTieMark.png", 32), ("QingTieMark@2x.png", 64)] {
    try render(size: size) { fitStandalonePages { drawPages(mark: true) } }.write(to: resources.appendingPathComponent(name))
  }
  for (name, size) in [("QingTieMenuTemplate.png", 18), ("QingTieMenuTemplate@2x.png", 36)] {
    try render(size: size, draw: drawMenuTemplate).write(to: resources.appendingPathComponent(name))
  }
}
