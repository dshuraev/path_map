# PathMap

Deterministic nested-map access/update, with explicit error semantics and controlled key creation.

- operates on *pure (possibly nested) Elixir maps*
- uses *paths* (lists of keys) to address nested location
- provides *strict* and *auto-vivifying* API variants

What it's not (yet):

- no general "lens DSL" (filters, recursion, multi-focus)
- no support for arbitrary containers (lists/tuples/structs)
- no schema engine

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `path_map` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:path_map, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/path_map>.
