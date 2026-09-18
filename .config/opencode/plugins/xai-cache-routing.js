export const XaiCacheRouting = async () => ({
  "chat.headers": async (input, output) => {
    if (input.model.providerID === "xai") output.headers["x-grok-conv-id"] = input.sessionID
  },
})
