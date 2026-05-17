import ConfettiSwiftUI
import Foundation

enum ConfettiObjects {
    static let captureLeft: [ConfettiType] = [
        .sfSymbol(symbolName: "bolt.fill"),
        .sfSymbol(symbolName: "camera.aperture"),
        .sfSymbol(symbolName: "camera.shutter.button.fill"),
        .sfSymbol(symbolName: "cloud.sun.fill"),
        .sfSymbol(symbolName: "rainbow"),
        .sfSymbol(symbolName: "bird"),
        .image("camera.blueberry"),
        .text("🫐"),
        .text("🌉"),
        .text("🌅"),
        .text("🍛"),
        .text("🏎️"),
        .text("🏀"),
        .text("🏈"),
    ]
    
    static let captureRight: [ConfettiType] = [
        .sfSymbol(symbolName: "camera.macro"),
        .sfSymbol(symbolName: "camera.filters"),
        .sfSymbol(symbolName: "photo.stack.fill"),
        .sfSymbol(symbolName: "cloud.bolt.rain"),
        .sfSymbol(symbolName: "person.fill"),
        .sfSymbol(symbolName: "mountain.2"),
        .text("📸"),
        .text("🌤️"),
        .text("🌄"),
        .text("🌃"),
        .text("🐶"),
        .text("🚙"),
        .text("⚽️"),
    ]
    
    static let themesLeft: [ConfettiType] = [
        .sfSymbol(symbolName: "bolt.fill"),
        .sfSymbol(symbolName: "camera.shutter.button.fill"),
        .sfSymbol(symbolName: "rainbow"),
        .sfSymbol(symbolName: "camera.macro"),
        .sfSymbol(symbolName: "photo.stack.fill"),
        .sfSymbol(symbolName: "person.fill"),
        .image("camera.blueberry"),
        .sfSymbol(symbolName: "leaf.fill"),
        .text("🌸"),
        .text("🌷"),
        .text("🌻"),
        .text("🌴"),
        .text("🍀"),
        .text("🫐"),
        .text("🔴"),
        .text("🔵"),
        .text("🟤"),
        .text("🟡"),
        .text("⚫️"),
        .text("💙"),
    ]
    
    static let themesRight: [ConfettiType] = [
        .sfSymbol(symbolName: "camera.aperture"),
        .sfSymbol(symbolName: "cloud.sun.fill"),
        .sfSymbol(symbolName: "bird"),
        .sfSymbol(symbolName: "camera.filters"),
        .sfSymbol(symbolName: "cloud.bolt.rain"),
        .sfSymbol(symbolName: "mountain.2"),
        .sfSymbol(symbolName: "tree.fill"),
        .text("🌹"),
        .text("🌺"),
        .text("🌼"),
        .text("🌲"),
        .text("🌳"),
        .text("🍁"),
        .text("🎨"),
        .text("⚪️"),
        .text("🟠"),
        .text("🟢"),
        .text("🟣"),
        .text("🧡"),
        .text("🩶"),
    ]
}
