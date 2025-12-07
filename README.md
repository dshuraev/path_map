# PathMap

[![Hex.pm](https://img.shields.io/hexpm/v/path_map.svg)](https://hex.pm/packages/path_map)
[![Hexdocs](https://img.shields.io/badge/docs-hexdocs.pm-blue)](https://hexdocs.pm/path_map)

Deterministic helpers for traversing and mutating nested maps using explicit
paths (lists of keys). Every call validates inputs, refuses to guess, and
returns tagged results instead of raising.

- pure Elixir maps only (no structs/lists/tuples)
- paths are lists; empty path (`[]`) targets the root
- strict and auto-vivifying variants for writes
- explicit `{:ok, value}` / `{:error, reason}` semantics

## Purpose

PathMap focuses on predictability and safety for nested map operations without
introducing a DSL or macros. If you want small, composable functions that tell
you exactly why traversal failed, this library is for you.

## Quick example

```elixir
map = %{"config" => %{"port" => 4000}}

# Strict read
{:ok, 4000} = PathMap.fetch(map, ["config", "port"])

# Strict write (fails because the path is missing)
{:error, {:missing, ["config", "db"]}} = PathMap.put(map, ["config", "db", "port"], 5432)

# Auto-vivifying write
{:ok, map} = PathMap.put_auto(map, ["config", "db", "port"], 5432)
5432 = map["config"]["db"]["port"]

# Update with default and auto-vivify
{:ok, map} = PathMap.update_auto(%{}, [:a, :b], 0, &(&1 + 1))
1 = get_in(map, [:a, :b])
```

## Core behaviors

- `fetch/2` returns `{:ok, value}` or `{:error, reason}`; root type is checked
  before path validity.
- `get/3` collapses any error to a default (nil by default).
- Strict writes (`put/3`, `put_new/3`, `update/3`, `update/4`) require the path
  to exist.
- Auto-vivifying writes (`put_auto/3`, `put_new_auto/3`, `update_auto/4`) create
  missing maps on the way.
- Empty path (`[]`) targets or replaces the entire map.

### Error shapes

- `{:not_a_map, value, prefix}` — traversal hit a non-map (root or intermediate)
- `{:missing, prefix}` — strict operation expected a key that was missing
- `{:invalid_initializer, initializer}` — `ensure/3` initializer is not arity 0
- `{:invalid_function, fun, arity}` — updater functions are wrong arity
- `:invalid_path` — path is not a list
- `:already_exists` — `put_new*/3` refused to overwrite an existing value
- `:leaf_missing` — `update/3` expected a leaf that was not present

## When to use PathMap

- You need deterministic, explicit error reporting for nested map updates.
- You want strict vs auto-vivifying control without learning a DSL.
- You are working with plain maps and want small, composable functions.
- You want to keep error handling at the call site instead of rescuing exceptions.

## When not to use PathMap

- You need optics over structs, lists, tuples, or multiple foci.
- You want declarative traversal/transformation DSLs or compile-time lenses.
- You need performance over complex data structures where a richer lens library
  shines.

## Comparison

### vs [Pathex](https://github.com/hissssst/pathex)

- Pathex offers a macro DSL for lenses/paths over many data types (maps,
  lists, structs) with composable optics and transformations.
- PathMap is smaller, works on maps only, and favors explicit return values
  over macros and compile-time generation.
- Choose PathMap when you want simple, defensive map traversal without DSL
  ceremony; choose Pathex when you need broad container support and lens
  composition.

### vs [lens](https://github.com/obrok/lens)

- `lens` provides composable optics and functional patterns for many data types.
- PathMap does not offer optics; it supplies straightforward functions for
  maps with clear error tuples.
- Choose PathMap when you prefer concrete functions and explicit failure
  reasons; choose `lens` when you need rich lens composition and container
  flexibility.

## API highlights

- Read:
  - `fetch/2` — returns `{:ok, value}` or `{:error, reason}`
  - `get/3` — returns value or default on any error
  - `exists?/2`, `validate_path/2`, `valid_path?/2`
- Write (strict):
  - `put/3` — replace at path (fails if missing)
  - `put_new/3` — insert only when missing
  - `update/3` — update existing leaf (fails with `:leaf_missing`)
  - `update/4` — update or set default at the leaf
- Write (auto-vivifying):
  - `put_auto/3`, `put_new_auto/3`, `update_auto/4`
- Utilities:
  - `ensure/3` — initialize missing leaf with a 0-arity function

See doctests in `lib/path_map.ex` and `test/path_map_test.exs` for detailed
examples and edge cases.

## Documentation

Full API docs live at [hexdocs.pm/path_map](https://hexdocs.pm/path_map).

## Requirements

- Elixir `~> 1.19`

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

Released under the MIT License. See [LICENSE](LICENSE) for details.

## Installation

Add to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:path_map, "~> 0.1.0"}
  ]
end
```
