---
name: agent-browser
description: Drive a browser from the shell with agent-browser to navigate, fill forms, click, screenshot and extract page content. Use for web testing and browser automation.
---

# Browser automation with agent-browser

`agent-browser --help` lists every command; `agent-browser <command> --help` gives its flags.

## Workflow

1. `agent-browser open <url>`
2. `agent-browser snapshot -i` lists the interactive elements with refs such as `@e1`.
3. Act on the refs: `click @e1`, `fill @e2 "text"` (clears first), `type @e2 "text"`,
   `press Enter`, `select @e1 "value"`, `check @e1`, `hover @e1`, `scroll down 500`.
4. Snapshot again after any navigation or DOM change; refs do not survive it.

```bash
agent-browser open https://example.com/form
agent-browser snapshot -i
# textbox "Email" [ref=e1], textbox "Password" [ref=e2], button "Submit" [ref=e3]
agent-browser fill @e1 "user@example.com"
agent-browser fill @e2 "password123"
agent-browser click @e3
agent-browser wait --load networkidle
agent-browser snapshot -i
```

## Useful beyond the basics

```bash
agent-browser get text @e1                    # also: get value @e1, get title, get url
agent-browser screenshot --full path.png      # full page to a file
agent-browser set viewport 1920 1080          # fix the viewport size
agent-browser wait --load networkidle         # also: wait @e1, wait 2000, wait --text "Success"
agent-browser find role button click --name "Submit"   # semantic locator instead of a ref
agent-browser state save auth.json            # reuse a login later with state load auth.json
agent-browser --session x open <url>          # parallel browsers; session list shows them
agent-browser snapshot -i --json              # machine-readable output
agent-browser errors                          # page errors; console for console messages
agent-browser open <url> --headed             # show the window
```
