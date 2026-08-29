import Foundation

struct AskBundledKnowledgeStore {
    struct Item: Decodable, Equatable {
        let sourceID: String
        let aliases: [String]
        let answer: String
        enum CodingKeys: String, CodingKey {
            case sourceID = "source_id"
            case aliases, answer
        }
    }

    private let items: [Item]

    init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "ask_knowledge_zh", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Item].self, from: data) else {
            items = []
            return
        }
        items = decoded
    }

    init(items: [Item]) { self.items = items }

    func answer(for message: String) -> Item? {
        let normalized = message.lowercased()
        guard ["什么", "代表", "怎么理解", "如何理解", "what is", "what does", "understand"]
            .contains(where: normalized.contains) else { return nil }
        return items.first { item in item.aliases.contains { normalized.contains($0.lowercased()) } }
    }
}
