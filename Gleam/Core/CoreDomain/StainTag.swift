import Foundation

struct StainTag: Identifiable, Hashable {
    let id: String
    let title: String
    let promptKeyword: String

    static let defaults: [StainTag] = [
        StainTag(id: "coffee", title: "Coffee", promptKeyword: "coffee"),
        StainTag(id: "red_wine", title: "Red wine", promptKeyword: "red wine"),
        StainTag(id: "cola", title: "Cola & soda", promptKeyword: "sugary dark soda"),
        StainTag(id: "tea", title: "Tea", promptKeyword: "dark tea"),
        StainTag(id: "smoking", title: "Smoking", promptKeyword: "tobacco smoke")
    ]
}
