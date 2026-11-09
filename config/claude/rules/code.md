# Code

## Type JSON with Serde

In Rust, every JSON shape the code builds or reads is a struct or enum deriving `Serialize`
and `Deserialize`. Never use a `serde_json::json!` literal or an index into a
`serde_json::Value`. A type names its fields where a reader looks for them. The compiler
rejects a renamed or missing field, which a `json!` literal ships without a word.

- **An API that accepts JSON takes a type or `impl Serialize`**, never `serde_json::Value`.
  A `Value` parameter leaves every caller one `json!` away from an untyped payload, so fix
  the signature in the library before its callers multiply.
- **Existing `json!` is not precedent.** Match the surrounding code's naming and layout, and
  write the type anyway.
- **Wire names come from attributes**, such as `#[serde(rename_all = "camelCase")]`, not from
  string keys spelled at each call site.
- **`Value` stays only where the shape is open**: a vendor payload passed through verbatim,
  or a column that stores arbitrary documents. Deserialize the fields the code reads from it
  into a type.
- **Tests follow the same rule.** A fixture is a value of the type under test, serialized.
