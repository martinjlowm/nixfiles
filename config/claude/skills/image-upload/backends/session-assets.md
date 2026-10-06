# session-assets backend

Uploads to the agent fleet's S3 bucket. GitHub embeds the file from a public URL under the
console domain. Fleet containers use it; they have no `gh image` and no browser session.

## Preflight

```bash
agent-image-upload --check
```

Exit 0 means uploads will work.

## Upload

```bash
agent-image-upload <file>
```

- One file per call. It prints the file's public URL on stdout, bare, so wrap it as the
  skill's [Uploading](../SKILL.md#uploading) section says.
- Only `png`, `jpg`, `jpeg`, `gif` and `webp` are accepted, because nothing serves any other
  type. Put logs and other text in the comment as a fenced block.

## Visibility

Public. Anyone holding the URL can open the file, whatever the target repository's
visibility. The fleet's owner accepted that for every repository the fleet posts to, so a
private target is no reason to stop. The image's content decides instead. Never upload one
that shows a credential, a token, customer data or a support ticket's contents.

## Recovery

Nobody is there to ask. When the preflight fails, keep the local files, post the comment
without images, and say in the comment and in the final message that the upload preflight
failed, quoting its error.
