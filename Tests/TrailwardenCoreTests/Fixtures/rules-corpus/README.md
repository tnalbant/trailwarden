# Rule corpus

Synthetic commands and file events used by `RuleCorpusTests` to measure how the
built-in rules behave: how many benign entries raise an alert (false alarms) and
how many risky entries are caught. Nothing here comes from a real transcript.

Format, one entry per line:

- `benign-bash.txt`: the command. A newline inside a command is written as the two characters `\n`; a backslash as `\\`.
- `benign-files.txt`: `Tool<TAB>path`.
- `risky.txt`: `category<TAB>command`.

Secret-shaped values are never written out, because the secret scan covers the
whole git history. The loader replaces these placeholders with values it
assembles at runtime from fragments:

- `{{GITHUB_TOKEN}}`
- `{{OPENAI_KEY}}`
- `{{ANTHROPIC_KEY}}`
- `{{AWS_KEY_ID}}`

The placeholder values are generated at test time and differ in shape from the
original Python corpus this was derived from, so the frozen thresholds in
`testCorpusDoesNotRegress` are this Swift corpus's own baseline, not numbers
comparable with the Python measurements.
