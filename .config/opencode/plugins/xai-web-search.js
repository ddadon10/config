export const XaiWebSearch = async ({ client }) => ({
  tool: {
    xai_web_search: {
      description:
        "Search the live web with xAI for up-to-date information and source links. " +
        "Use for requested web searches, citations, or facts that may have changed.",
      args: { query: { type: "string", description: "A web search query" } },
      async execute({ query }, context) {
        const { data } = await client.config.providers()
        const apiKey = data?.providers.find((provider) => provider.id === "xai")?.key
        if (!apiKey) throw new Error("Connect xAI with /connect first")

        const response = await fetch("https://api.x.ai/v1/responses", {
          method: "POST",
          headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
          body: JSON.stringify({
            model: "grok-4.6",
            input: `Query: ${query}`,
            instructions: "Do one web search. Answer briefly with a list of source links; prefer primary sources.",
            reasoning: { effort: "low" },
            max_output_tokens: 2000,
            max_turns: 3,
            parallel_tool_calls: false,
            store: false,
            tools: [{ type: "web_search" }],
          }),
          signal: context.abort,
        })

        if (!response.ok) throw new Error(`xAI web search failed (${response.status})`)
        const result = await response.json()
        return result.output.flatMap((item) => item.content ?? []).map((part) => part.text).filter(Boolean).join("\n")
      },
    },
  },
})
