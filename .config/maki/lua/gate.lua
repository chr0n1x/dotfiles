-- gate: yes/no confirmation as a selectable prompt.
-- The question tool's payload nests options under questions; this tool
-- takes flat strings and builds that structure, then calls question.

maki.api.register_tool({
  name = "gate",
  description = [[Confirm a yes/no decision with the user as a selectable prompt.
Use for push gates, stack mutations, and any hard gate the commit-push or
gh-stack skills require. Takes the question text plus what each answer does.
Returns "yes", "no", or the user's free-text answer.]],
  schema = {
    type = "object",
    required = { "question" },
    additionalProperties = false,
    properties = {
      question = { type = "string", description = "The question to ask" },
      yes = { type = "string", description = "What selecting yes will do (shown under the yes option)" },
      no = { type = "string", description = "What selecting no will do (shown under the no option)" },
    },
  },
  handler = function(input, ctx)
    local question = input.question
    if not question or question == "" then
      return { llm_output = "error: question is required", is_error = true }
    end

    local payload = {
      questions = {
        {
          question = question,
          header = "confirm",
          options = {
            { label = "yes", description = input.yes or "proceed" },
            { label = "no", description = input.no or "do not proceed" },
          },
          multiSelect = false,
        },
      },
    }

    local out, err = maki.agent.call_tool(ctx, "question", payload)
    if err then
      return { llm_output = "error: " .. err, is_error = true }
    end
    return { llm_output = out or "(no answer)" }
  end,
})
