#!/usr/bin/swift

// generate-icon.swift
// Generates an AppIcon.icon for any Tiny* app.
//
// Usage: swift scripts/generate-icon.swift <TEXT> <ACCENT_HEX> [output_dir]
//   TEXT:       Extension label, e.g. "MD", "JSON", "YAML"
//   ACCENT_HEX: Hex color, e.g. "#2DD4BF" (teal)
//   output_dir:  Optional, defaults to ./AppIcon.icon
//
// Example: swift scripts/generate-icon.swift MD "#2DD4BF"

import AppKit
import CoreGraphics

// MARK: - Color helpers

func hexToP3(_ hex: String) -> (r: Double, g: Double, b: Double) {
    let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    let scanner = Scanner(string: h)
    var rgb: UInt64 = 0
    scanner.scanHexInt64(&rgb)
    return (
        r: Double((rgb >> 16) & 0xFF) / 255.0,
        g: Double((rgb >> 8) & 0xFF) / 255.0,
        b: Double(rgb & 0xFF) / 255.0
    )
}

func p3String(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1.0) -> String {
    String(format: "display-p3:%.5f,%.5f,%.5f,%.5f", r, g, b, a)
}

func darken(_ r: Double, _ g: Double, _ b: Double, factor: Double = 0.6) -> (Double, Double, Double) {
    (r * factor, g * factor, b * factor)
}

// MARK: - Generate PNG

func generateTextPNG(text: String, outputPath: String) {
    // Canvas: 486x315
    let width = 486
    let height = 315

    let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        print("Failed to create CGContext")
        exit(1)
    }

    // Transparent background
    ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))

    // Draw text
    let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx

    // Auto-fit: start at 340pt and scale down until text fits ~70% of canvas
    // Extra padding needed because macOS icon renderer clips inside rounded rect
    let maxWidth = CGFloat(width) * 0.70
    let maxHeight = CGFloat(height) * 0.70
    var fontSize: CGFloat = 340
    var font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
    var attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.black,
    ]
    var str = NSAttributedString(string: text, attributes: attrs)
    var size = str.size()

    while (size.width > maxWidth || size.height > maxHeight) && fontSize > 40 {
        fontSize -= 10
        font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        attrs[.font] = font
        str = NSAttributedString(string: text, attributes: attrs)
        size = str.size()
    }

    let x = (CGFloat(width) - size.width) / 2
    let y = (CGFloat(height) - size.height) / 2
    str.draw(at: NSPoint(x: x, y: y))

    NSGraphicsContext.restoreGraphicsState()

    guard let image = ctx.makeImage() else {
        print("Failed to create image")
        exit(1)
    }

    let url = URL(fileURLWithPath: outputPath)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        print("Failed to create image destination")
        exit(1)
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// MARK: - Generate icon.json

func generateIconJSON(accentHex: String, textLength: Int) -> String {
    // Scale glyph down for longer text to prevent clipping in rounded rect
    let glyphScale: Double = textLength <= 2 ? 1.0 : 0.75
    let (r, g, b) = hexToP3(accentHex)
    let (dr, dg, db) = darken(r, g, b, factor: 0.4)

    // Light: white top → accent bottom
    let lightTop = p3String(1.0, 1.0, 1.0)
    let lightBottom = p3String(r, g, b)

    // Dark: lighter accent top → dark accent bottom
    let darkTop = p3String(r * 0.5, g * 0.5, b * 0.5)
    let darkBottom = p3String(dr, dg, db)

    return """
    {
      "fill-specializations" : [
        {
          "value" : {
            "linear-gradient" : [
              "\(lightTop)",
              "\(lightBottom)"
            ],
            "orientation" : {
              "start" : { "x" : 0.5, "y" : 0 },
              "stop" : { "x" : 0.5, "y" : 1.0 }
            }
          }
        },
        {
          "appearance" : "dark",
          "value" : {
            "linear-gradient" : [
              "\(darkTop)",
              "\(darkBottom)"
            ],
            "orientation" : {
              "start" : { "x" : 0.5, "y" : 0 },
              "stop" : { "x" : 0.5, "y" : 1.0 }
            }
          }
        }
      ],
      "groups" : [
        {
          "layers" : [
            {
              "fill-specializations" : [
                {
                  "appearance" : "dark",
                  "value" : {
                    "solid" : "extended-gray:1.00000,1.00000"
                  }
                }
              ],
              "glass" : false,
              "image-name" : "glyph.png",
              "name" : "glyph",
              "position" : {
                "scale" : \(glyphScale),
                "translation-in-points" : [ 0, 0 ]
              }
            }
          ],
          "shadow" : {
            "kind" : "neutral",
            "opacity" : 0.5
          },
          "translucency" : {
            "enabled" : true,
            "value" : 0.5
          }
        }
      ],
      "supported-platforms" : {
        "circles" : [ "watchOS" ],
        "squares" : "shared"
      }
    }
    """
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("Usage: swift \(args[0]) <TEXT> <ACCENT_HEX> [output_dir]")
    print("Example: swift \(args[0]) MD \"#2DD4BF\"")
    exit(1)
}

let text = args[1]
let accentHex = args[2]
let outputDir = args.count > 3 ? args[3] : "AppIcon.icon"

// Create directory structure
let assetsDir = "\(outputDir)/Assets"
let fm = FileManager.default
try? fm.createDirectory(atPath: assetsDir, withIntermediateDirectories: true)

// Generate glyph PNG
let pngPath = "\(assetsDir)/glyph.png"
generateTextPNG(text: text, outputPath: pngPath)
print("Generated \(pngPath)")

// Generate icon.json
let jsonPath = "\(outputDir)/icon.json"
let json = generateIconJSON(accentHex: accentHex, textLength: text.count)
try! json.write(toFile: jsonPath, atomically: true, encoding: .utf8)
print("Generated \(jsonPath)")

print("Done! AppIcon.icon ready at \(outputDir)/")
