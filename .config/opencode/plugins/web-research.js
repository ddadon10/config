export const WebResearch = async ({ client }) => ({
  tool: {
    web_research: {
      description:
        "Research the live web for up-to-date information, citations, and further reading. " +
        "Use for requested web searches or facts that may have changed.",
      args: { query: { type: "string", description: "A web search query" } },
      async execute({ query }, context) {
        const { data } = await client.config.providers()
        const apiKey = data?.providers.find((provider) => provider.id === "openrouter")?.key
        if (!apiKey) throw new Error("Connect OpenRouter with /connect first")

        const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
          method: "POST",
          headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
          body: JSON.stringify({
            model: "perplexity/sonar",
            provider: { only: ["perplexity"] },
            messages: [
              {
                role: "system",
                content:
                  "Use two sections: Answer and Further reading. Cite at most 10 distinct pages, prioritizing primary evidence. " +
                  "Explain what each further-reading source adds. Do not ask follow-up questions or offer further assistance.",
              },
              { role: "user", content: query },
            ],
            max_completion_tokens: 2000,
          }),
          signal: context.abort,
        })

        if (!response.ok) throw new Error(`Web research failed (${response.status})`)
        const result = await response.json()
        const choice = result.choices?.[0]
        if (result.error || choice?.error || !choice?.message) {
          throw new Error(`Web research failed: ${result.error?.message ?? choice?.error?.message ?? "no message"}`)
        }
        return [choice.message.content, "", ...(choice.message.annotations ?? []).map((item, index) =>
          `[${index + 1}] ${item.url_citation?.url}`)].join("\n")
      },
    },
  },
})
