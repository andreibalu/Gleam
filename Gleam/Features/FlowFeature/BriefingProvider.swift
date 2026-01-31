import Foundation

struct DailyBriefing: Identifiable {
    let id = UUID()
    let category: String
    let content: String
    let author: String?
}

struct BriefingProvider {
    static let shared = BriefingProvider()
    
    private let briefings: [DailyBriefing] = [
        DailyBriefing(category: "Mindfulness", content: "Smile, breathe, and go slowly.", author: "Thich Nhat Hanh"),
        DailyBriefing(category: "Wisdom", content: "The only way to do great work is to love what you do.", author: "Steve Jobs"),
        DailyBriefing(category: "Health", content: "Brushing for 2 minutes removes 2x more plaque than 45 seconds.", author: nil),
        DailyBriefing(category: "Focus", content: "Where your attention goes, your energy flows.", author: nil),
        DailyBriefing(category: "Stoic", content: "Waste no more time arguing what a good man should be. Be one.", author: "Marcus Aurelius"),
        DailyBriefing(category: "Wellness", content: "A smile is a curve that sets everything straight.", author: "Phyllis Diller"),
        DailyBriefing(category: "Fact", content: "Enamel is the hardest substance in the human body.", author: nil),
        DailyBriefing(category: "Morning", content: "Write it on your heart that every day is the best day in the year.", author: "Ralph Waldo Emerson"),
        DailyBriefing(category: "Evening", content: "Finish each day and be done with it. You have done what you could.", author: "Ralph Waldo Emerson"),
        DailyBriefing(category: "Zen", content: "When you do something, you should burn yourself up completely, like a good bonfire, leaving no trace of yourself.", author: "Shunryu Suzuki")
    ]
    
    func dailyBriefing() -> DailyBriefing {
        // In a real app, this might pick based on day of year to ensure consistency per day
        // For now, random is fine for variety
        briefings.randomElement() ?? briefings[0]
    }
}
