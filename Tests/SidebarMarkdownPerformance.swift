import Foundation

@main struct SidebarMarkdownPerformance {
    static func main() {
        let source = (0..<150).map { "## Section \($0)\nParagraph with **bold** and `code`.\n\n```sql\nSELECT \($0);\n```\n" }.joined()
        let cache = AgentMarkdownCache()
        let expected = AgentMarkdownBlock.parse(source)
        precondition(cache.blocks(for: source) == expected)
        let start = Date()
        for _ in 0..<100 { precondition(AgentMarkdownBlock.parse(source) == expected) }
        let uncached = Date().timeIntervalSince(start)
        let cachedStart = Date()
        for _ in 0..<100 { precondition(cache.blocks(for: source) == expected) }
        let cached = Date().timeIntervalSince(cachedStart)
        let changed = source + "\nNew streaming content"
        precondition(cache.blocks(for: changed) == AgentMarkdownBlock.parse(changed))
        precondition(cache.blocks(for: "").isEmpty)
        let inline = AgentInlineCache()
        precondition(String(inline.value(for: "**First**").characters) == "First")
        precondition(String(inline.value(for: "Second").characters) == "Second")
        print(String(format: "100 unchanged Markdown updates: parse %.3f s; cached %.3f s", uncached, cached))
        print("PASS: unchanged content reuse, streaming content invalidation, empty content, inline text updates")
    }
}
