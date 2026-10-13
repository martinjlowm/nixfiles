# Disclosure

The disclosure marks text on GitHub as written by an agent under a person's name. It is this
line, on its own line, with the model named as your system prompt names it, such as `Opus 5.5`:

```
<sub>Made with ❤️ by Claude (<model>)</sub>
```

The agent-guard hook refuses a post that carries no disclosure, and taking a PR out of draft
appends `, reviewed` after the closing parenthesis.
