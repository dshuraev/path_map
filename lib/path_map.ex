defmodule PathMap do
  @moduledoc """
  PathMap provides deterministic helpers for traversing and mutating nested maps
  using explicit *paths* (lists of keys).

  Paths can be empty (`[]`, meaning the root map) or lists like `[:a, "b"]`.
  Keys are not restricted to atoms.

  Every public function validates inputs and returns tagged errors instead of
  raising. The root is checked first, so a non-map root yields
  `{:error, {:not_a_map, root, []}}` even if the path is invalid.

  The API comes in two families:
  - strict (`put/3`, `put_new/3`, `update/3`, etc.) require each path segment to exist
  - auto-vivifying (`put_auto/3`, `put_new_auto/3`, `update_auto/4`) create
    missing maps on the way

  Error tuples you may see:
  - `:invalid_path` when the path is not a list
  - `{:not_a_map, value, prefix}` when traversal hits a non-map at `prefix`
  - `{:missing, prefix}` when a strict operation needs a missing key
  - `:already_exists` when `put_new*/3` refuses to overwrite
  - `{:invalid_function, fun, arity}` and `{:invalid_initializer, init}` when
    callbacks have the wrong shape
  - `:leaf_missing` when `update/3` expects a leaf that is not present

  ## Examples

      iex> map = %{"config" => %{"port" => 4000}}
      iex> PathMap.fetch(map, ["config", "port"])
      {:ok, 4000}

      iex> map = %{"config" => %{"port" => 4000}}
      iex> PathMap.put(map, ["config", "db", "port"], 5432)
      {:error, {:missing, ["config", "db"]}}
      iex> {:ok, with_db} = PathMap.put_auto(map, ["config", "db", "port"], 5432)
      iex> with_db["config"]["db"]["port"]
      5432

      iex> PathMap.get(%{"config" => 1}, :bad_path, :fallback)
      :fallback

      iex> PathMap.update_auto(%{"config" => "not a map"}, ["config", "port"], 4000, & &1)
      {:error, {:not_a_map, "not a map", ["config"]}}
  """

  @type key :: term()
  @type val :: term()

  @typedoc """
  `path` is an ordered list of keys that represents a location within `PathMap`.

  Can be empty `[]` or non-empty `[key | rest]`.
  """
  @type path :: list(key())

  @typedoc """
  `PathMap` is a nested map, where values can be arbitrary terminal values or
  other maps (subtrees).

  `PathMap` does not enforce homogeneity of values.
  """
  @type t :: %{key() => val()}

  @type err_not_a_map :: {:error, {:not_a_map, term(), path()}}
  @type err_missing :: {:error, {:missing, path()}}
  @type err_invalid_path :: {:error, :invalid_path}
  @type err_invalid_fun :: {:error, {:invalid_function, term(), arity :: non_neg_integer()}}
  @type err_invalid_initializer :: {:error, {:invalid_initializer, term()}}

  # SECTION - Read API
  @doc """
  Fetches a value from `map` at `path`.

  `path` must be a list; the empty list returns the full map. The root being a
  non-map is reported before path validation.

  Returns:
  - `{:ok, value}` when the path can be traversed
  - `{:error, :invalid_path}` when `path` is not a list
  - `{:error, {:missing, prefix}}` when any segment does not exist
  - `{:error, {:not_a_map, val, prefix}}` when a non-map is encountered

  ## Examples

      iex> PathMap.fetch(%{a: %{b: 1}}, [:a, :b])
      {:ok, 1}

      iex> PathMap.fetch(%{a: %{b: 1}}, [])
      {:ok, %{a: %{b: 1}}}

      iex> PathMap.fetch(%{a: 1}, [:a, :b])
      {:error, {:not_a_map, 1, [:a]}}

      iex> PathMap.fetch(%{}, :not_a_list)
      {:error, :invalid_path}

      iex> PathMap.fetch(:root_is_wrong, [])
      {:error, {:not_a_map, :root_is_wrong, []}}
  """
  @spec fetch(t(), path()) ::
          {:error, {:not_a_map, val(), path()} | {:missing, path()} | :invalid_path}
          | {:ok, val()}

  def fetch(map, path) do
    cond do
      not is_map(map) -> {:error, {:not_a_map, map, []}}
      not is_list(path) -> {:error, :invalid_path}
      true -> fetch_nested(map, path, [])
    end
  end

  defp fetch_nested(map, [], _acc) when is_map(map), do: {:ok, map}

  defp fetch_nested(map, [key], acc) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, val} -> {:ok, val}
      :error -> {:error, {:missing, Enum.reverse(acc, [key])}}
    end
  end

  defp fetch_nested(map, [key | rest], acc) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, val} -> fetch_nested(val, rest, [key | acc])
      :error -> {:error, {:missing, Enum.reverse(acc, [key])}}
    end
  end

  defp fetch_nested(val, _path, acc), do: {:error, {:not_a_map, val, Enum.reverse(acc)}}

  @doc """
  Gets a value from `map` by its `path`.

  Returns the provided `default` (nil by default) on *any* error, including a
  non-map root or an invalid path type.

  ## Examples

      iex> PathMap.get(%{a: %{b: 1}}, [:a, :b])
      1

      iex> PathMap.get(%{}, [:missing], :none)
      :none

      iex> PathMap.get(:not_a_map, [:a], :none)
      :none
  """
  @spec get(t(), path(), default) :: val() | default when default: term()
  def get(map, path, default \\ nil) do
    case fetch(map, path) do
      {:ok, val} -> val
      {:error, _} -> default
    end
  end

  @doc """
  Checks if a given `path` exists in `map`.

  Delegates to `fetch/2` and collapses any error into `false`, including
  invalid path types or non-map roots.

  ## Examples

      iex> PathMap.exists?(%{a: %{b: 1}}, [:a, :b])
      true

      iex> PathMap.exists?(%{}, :bad_path)
      false
  """
  @spec exists?(t(), path()) :: boolean()
  def exists?(map, path) do
    case fetch(map, path) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Validates a given `path` of `map`.

  Thin wrapper around `fetch/2` that returns `:ok` on success or the same error
  tuple as `fetch/2` on failure.

  ## Examples

      iex> PathMap.validate_path(%{a: %{b: 1}}, [:a, :b])
      :ok

      iex> PathMap.validate_path(%{}, [:missing])
      {:error, {:missing, [:missing]}}
  """
  @spec validate_path(t(), path()) ::
          :ok
          | {:error, {:not_a_map, val(), path()} | {:missing, path()} | :invalid_path}
  def validate_path(map, path) do
    case fetch(map, path) do
      {:ok, _} -> :ok
      e -> e
    end
  end

  @doc """
  Boolean version of `validate_path/2`.

  Returns `true` when the path can be traversed, `false` otherwise.

  ## Examples

      iex> PathMap.valid_path?(%{a: 1}, [:a])
      true

      iex> PathMap.valid_path?(%{}, [:a, :b])
      false
  """
  @spec valid_path?(t(), path()) :: boolean()
  def valid_path?(map, path) do
    case validate_path(map, path) do
      :ok -> true
      {:error, _} -> false
    end
  end

  #!SECTION - Read API
  # SECTION - Write API

  @doc """
  Permissive insertion.

  Put `val` at `path` into `map`, auto-vivifying intermediate maps. An empty
  path replaces the entire map. Encountering a non-map stops traversal with
  `{:error, {:not_a_map, val, prefix}}`; root type check runs before path
  validation.

  Errors:
  - `{:error, :invalid_path}` if `path` is not a list
  - `{:error, {:not_a_map, val, prefix}}` if an intermediate subtree at `prefix` is not a map

  ## Examples

      iex> PathMap.put_auto(%{}, [:a, :b], 2)
      {:ok, %{a: %{b: 2}}}

      iex> PathMap.put_auto(%{a: 1}, [:a, :b], 2)
      {:error, {:not_a_map, 1, [:a]}}

      iex> PathMap.put_auto(:oops, [:a], 1)
      {:error, {:not_a_map, :oops, []}}
  """
  @spec put_auto(t(), path(), val()) ::
          {:ok, t()}
          | {:error, :invalid_path | {:not_a_map, val(), path()}}
  def put_auto(map, path, val) do
    cond do
      not is_map(map) -> {:error, {:not_a_map, map, []}}
      not is_list(path) -> {:error, :invalid_path}
      true -> put_auto_nested(map, path, val, [])
    end
  end

  # replace entire state with val
  defp put_auto_nested(map, [], val, _acc) when is_map(map), do: {:ok, val}

  # fast path
  defp put_auto_nested(map, [key], val, _acc) when is_map(map) do
    {:ok, Map.put(map, key, val)}
  end

  # normal path
  defp put_auto_nested(map, [key | rest], val, acc) when is_map(map) do
    next = Map.get(map, key, %{})

    case put_auto_nested(next, rest, val, [key | acc]) do
      {:ok, updated_next} -> {:ok, Map.put(map, key, updated_next)}
      {:error, _} = error -> error
    end
  end

  defp put_auto_nested(not_a_map, _path, _val, acc),
    do: {:error, {:not_a_map, not_a_map, Enum.reverse(acc)}}

  @doc """
  Strict insertion.

  Put `val` at `path` into `map`, failing if any part of the path is missing.
  `path == []` replaces the entire `map` with `val`. Missing segments return
  `{:error, {:missing, prefix}}`; encountering a non-map returns
  `{:error, {:not_a_map, val, prefix}}`.

  Errors:
  - `{:error, :invalid_path}` if `path` is not a list
  - `{:error, {:not_a_map, val, prefix}}` if the traversal encounters a non-map at `prefix`
  - `{:error, {:missing, prefix}}` if `prefix` in `path` does not exist

  ## Examples

      iex> PathMap.put(%{a: %{b: 1}}, [:a, :b], 2)
      {:ok, %{a: %{b: 2}}}

      iex> PathMap.put(%{}, [:a, :b], 1)
      {:error, {:missing, [:a]}}

      iex> PathMap.put(%{a: 1}, [:a, :b], 2)
      {:error, {:not_a_map, 1, [:a]}}

      iex> PathMap.put(%{a: 1}, [], :new)
      {:ok, :new}
  """
  @spec put(t(), path(), val()) ::
          {:ok, t()}
          | {:error, :invalid_path | {:not_a_map, val(), path()} | {:missing, path()}}
  def put(map, path, val) do
    cond do
      not is_map(map) -> {:error, {:not_a_map, map, []}}
      not is_list(path) -> {:error, :invalid_path}
      true -> put_nested(map, path, val, [])
    end
  end

  defp put_nested(map, [], val, _acc) when is_map(map), do: {:ok, val}

  defp put_nested(map, [key], val, _acc) when is_map(map) do
    {:ok, Map.put(map, key, val)}
  end

  defp put_nested(map, [key | rest], val, acc) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, next} ->
        case put_nested(next, rest, val, [key | acc]) do
          {:ok, updated_next} -> {:ok, Map.put(map, key, updated_next)}
          {:error, _} = error -> error
        end

      :error ->
        {:error, {:missing, Enum.reverse(acc, [key])}}
    end
  end

  defp put_nested(not_a_map, _path, _val, acc),
    do: {:error, {:not_a_map, not_a_map, Enum.reverse(acc)}}

  @doc """
  Put a new element at `path` with `val` without overwriting existing data.

  Traverses strictly (no auto-vivification). Missing intermediates yield
  `{:error, {:missing, prefix}}` and hitting a non-map yields
  `{:error, {:not_a_map, val, prefix}}`. Passing `[]` returns
  `{:error, :already_exists}`.

  ## Examples

      iex> PathMap.put_new(%{a: %{b: 1}}, [:a, :c], 2)
      {:ok, %{a: %{b: 1, c: 2}}}

      iex> PathMap.put_new(%{a: %{b: 1}}, [:a, :b], 2)
      {:error, :already_exists}

      iex> PathMap.put_new(%{}, [:a, :b], 1)
      {:error, {:missing, [:a]}}
  """
  @spec put_new(t(), path(), val()) ::
          {:ok, t()}
          | err_not_a_map()
          | err_invalid_path()
          | err_missing()
          | {:error, :already_exists}
  def put_new(map, path, val) do
    cond do
      not is_map(map) -> {:error, {:not_a_map, map, []}}
      not is_list(path) -> {:error, :invalid_path}
      true -> put_new_nested(map, path, val, [])
    end
  end

  defp put_new_nested(map, [], _val, _acc) when is_map(map), do: {:error, :already_exists}

  defp put_new_nested(map, [key], val, _acc) when is_map(map) do
    case Map.fetch(map, key) do
      :error -> {:ok, Map.put(map, key, val)}
      {:ok, _} -> {:error, :already_exists}
    end
  end

  defp put_new_nested(map, [key | rest], val, acc) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, next} ->
        case put_new_nested(next, rest, val, [key | acc]) do
          {:ok, updated_next} -> {:ok, Map.put(map, key, updated_next)}
          {:error, _} = error -> error
        end

      :error ->
        {:error, {:missing, Enum.reverse(acc, [key])}}
    end
  end

  defp put_new_nested(not_a_map, _path, _val, acc),
    do: {:error, {:not_a_map, not_a_map, Enum.reverse(acc)}}

  @doc """
  Put a new element at `path` with `val`, auto-vivifying missing maps.

  Returns `{:error, :already_exists}` when the leaf already exists. Encountering
  an existing non-map still returns `{:error, {:not_a_map, val, prefix}}`.
  Passing `[]` returns `{:error, :already_exists}`.

  ## Examples

      iex> PathMap.put_new_auto(%{}, [:a, :b, :c], 3)
      {:ok, %{a: %{b: %{c: 3}}}}

      iex> PathMap.put_new_auto(%{a: %{b: 1}}, [:a, :b], 2)
      {:error, :already_exists}

      iex> PathMap.put_new_auto(%{a: 1}, [:a, :b], 2)
      {:error, {:not_a_map, 1, [:a]}}
  """
  @spec put_new_auto(t(), path(), val()) ::
          {:ok, t()}
          | err_not_a_map()
          | err_invalid_path()
          | {:error, :already_exists}
  def put_new_auto(map, path, val) do
    cond do
      not is_map(map) -> {:error, {:not_a_map, map, []}}
      not is_list(path) -> {:error, :invalid_path}
      true -> put_new_auto_nested(map, path, val, [])
    end
  end

  defp put_new_auto_nested(map, [], _val, _acc) when is_map(map),
    do: {:error, :already_exists}

  defp put_new_auto_nested(map, [key], val, _acc) when is_map(map) do
    case Map.fetch(map, key) do
      :error -> {:ok, Map.put(map, key, val)}
      {:ok, _} -> {:error, :already_exists}
    end
  end

  defp put_new_auto_nested(map, [key | rest], val, acc) when is_map(map) do
    next = Map.get(map, key, %{})

    case put_new_auto_nested(next, rest, val, [key | acc]) do
      {:ok, updated_next} -> {:ok, Map.put(map, key, updated_next)}
      {:error, _} = error -> error
    end
  end

  defp put_new_auto_nested(not_a_map, _path, _val, acc),
    do: {:error, {:not_a_map, not_a_map, Enum.reverse(acc)}}

  @doc """
  Initialize an element at `path` with `initializer` function if it doesn't exist.

  Traverses the path without auto-vivifying, leaving the existing value intact
  when the element already exists. `initializer` must be a 0-arity function and
  is only executed when the leaf is missing. `path == []` is a no-op that
  returns `{:ok, map}`.

  Errors:
  - `{:error, :invalid_path}` if `path` is not a list
  - `{:error, {:not_a_map, val, prefix}}` if a non-map is encountered on the way
  - `{:error, {:missing, prefix}}` if part of the path does not exist
  - `{:error, {:invalid_initializer, initializer}}` if initializer is not a 0-arity function

  ## Examples

      iex> PathMap.ensure(%{a: %{b: 1}}, [:a, :b], fn -> 0 end)
      {:ok, %{a: %{b: 1}}}

      iex> PathMap.ensure(%{a: %{}}, [:a, :b], fn -> 2 end)
      {:ok, %{a: %{b: 2}}}

      iex> PathMap.ensure(%{}, [:a, :b], fn -> 2 end)
      {:error, {:missing, [:a]}}
  """
  @spec ensure(t(), path(), (-> val())) ::
          {:ok, t()}
          | err_not_a_map()
          | err_invalid_path()
          | err_missing()
          | err_invalid_initializer()
  def ensure(map, path, initializer) do
    cond do
      not is_map(map) -> {:error, {:not_a_map, map, []}}
      not is_list(path) -> {:error, :invalid_path}
      not is_function(initializer, 0) -> {:error, {:invalid_initializer, initializer}}
      true -> ensure_nested(map, path, initializer, [])
    end
  end

  defp ensure_nested(map, [], _initializer, _acc) when is_map(map), do: {:ok, map}

  defp ensure_nested(map, [key], initializer, _acc) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, _} -> {:ok, map}
      :error -> {:ok, Map.put(map, key, initializer.())}
    end
  end

  defp ensure_nested(map, [key | rest], initializer, acc) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, next} ->
        case ensure_nested(next, rest, initializer, [key | acc]) do
          {:ok, updated_next} -> {:ok, Map.put(map, key, updated_next)}
          {:error, _} = error -> error
        end

      :error ->
        {:error, {:missing, Enum.reverse(acc, [key])}}
    end
  end

  defp ensure_nested(not_a_map, _path, _initializer, acc),
    do: {:error, {:not_a_map, not_a_map, Enum.reverse(acc)}}

  @doc """
  Update an element at `path` with `function`.

  Traverses strictly (no auto-vivification). Returns `{:error, :leaf_missing}`
  when the terminal key is absent even if intermediates exist. `path == []`
  applies `function` to the entire map.

  Errors:
  - `{:error, :invalid_path}` if `path` is not a list
  - `{:error, {:invalid_function, fun, 1}}` if `function` is not arity-1
  - `{:error, {:missing, prefix}}` if an intermediate segment is missing
  - `{:error, {:not_a_map, val, prefix}}` if an intermediate value is not a map
  - `{:error, :leaf_missing}` if the final key is missing while intermediates exist

  ## Examples

      iex> PathMap.update(%{a: 1}, [:a], &(&1 + 1))
      {:ok, %{a: 2}}

      iex> PathMap.update(%{a: %{}}, [:a, :b], &(&1 + 1))
      {:error, :leaf_missing}

      iex> PathMap.update(%{a: 1}, [], &Map.put(&1, :b, 2))
      {:ok, %{a: 1, b: 2}}
  """
  @spec update(t(), path(), (val() -> val())) ::
          {:ok, t()}
          | err_not_a_map()
          | err_invalid_path()
          | err_missing()
          | {:error, :leaf_missing}
          | err_invalid_fun()
  def update(map, path, function) do
    cond do
      not is_map(map) -> {:error, {:not_a_map, map, []}}
      not is_list(path) -> {:error, :invalid_path}
      not is_function(function, 1) -> {:error, {:invalid_function, function, 1}}
      true -> update_nested(map, path, function, [])
    end
  end

  defp update_nested(map, [], function, _acc) when is_map(map), do: {:ok, function.(map)}

  defp update_nested(map, [key], function, _acc) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, val} -> {:ok, Map.put(map, key, function.(val))}
      :error -> {:error, :leaf_missing}
    end
  end

  defp update_nested(map, [key | rest], function, acc) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, next} ->
        case update_nested(next, rest, function, [key | acc]) do
          {:ok, updated_next} -> {:ok, Map.put(map, key, updated_next)}
          {:error, _} = error -> error
        end

      :error ->
        {:error, {:missing, Enum.reverse(acc, [key])}}
    end
  end

  defp update_nested(not_a_map, _path, _function, acc),
    do: {:error, {:not_a_map, not_a_map, Enum.reverse(acc)}}

  @doc """
  Update an element at `path` with `function`, inserting `default` when missing.

  Traverses strictly (no auto-vivification). Missing intermediate segments
  return `{:error, {:missing, prefix}}`; encountering a non-map returns
  `{:error, {:not_a_map, val, prefix}}`. When the final key is absent but the
  path exists so far, it is set to `default` without calling `function`. An
  empty path applies `function` to the root map.

  Errors:
  - `{:error, :invalid_path}` if `path` is not a list
  - `{:error, {:invalid_function, fun, 1}}` if `function` is not arity-1
  - `{:error, {:not_a_map, val, prefix}}` or `{:error, {:missing, prefix}}` for traversal issues

  ## Examples

      iex> PathMap.update(%{a: %{b: 1}}, [:a, :b], 0, &(&1 + 1))
      {:ok, %{a: %{b: 2}}}

      iex> PathMap.update(%{a: %{}}, [:a, :b], 5, &(&1 + 1))
      {:ok, %{a: %{b: 5}}}

      iex> PathMap.update(%{}, [:a, :b], 0, &(&1 + 1))
      {:error, {:missing, [:a]}}
  """
  @spec update(t(), path(), val(), (val() -> val())) ::
          {:ok, t()} | err_not_a_map() | err_invalid_path() | err_missing() | err_invalid_fun()
  def update(map, path, default, function) do
    cond do
      not is_map(map) -> {:error, {:not_a_map, map, []}}
      not is_list(path) -> {:error, :invalid_path}
      not is_function(function, 1) -> {:error, {:invalid_function, function, 1}}
      true -> update_with_default_nested(map, path, default, function, [])
    end
  end

  defp update_with_default_nested(map, [], _default, function, _acc) when is_map(map),
    do: {:ok, function.(map)}

  defp update_with_default_nested(map, [key], default, function, _acc) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, val} -> {:ok, Map.put(map, key, function.(val))}
      :error -> {:ok, Map.put(map, key, default)}
    end
  end

  defp update_with_default_nested(map, [key | rest], default, function, acc) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, next} ->
        case update_with_default_nested(next, rest, default, function, [key | acc]) do
          {:ok, updated_next} -> {:ok, Map.put(map, key, updated_next)}
          {:error, _} = error -> error
        end

      :error ->
        {:error, {:missing, Enum.reverse(acc, [key])}}
    end
  end

  defp update_with_default_nested(not_a_map, _path, _default, _function, acc),
    do: {:error, {:not_a_map, not_a_map, Enum.reverse(acc)}}

  @doc """
  Update an element at `path` with `function`, auto-vivifying missing maps.

  Missing leaves are initialized to `default` and then passed to `function`.
  Missing intermediates are created as `%{}`. `path == []` applies `function` to
  the root map. Fails when the root or an encountered value is not a map, when
  the path is not a list, or when `function` is not arity-1.

  ## Examples

      iex> PathMap.update_auto(%{}, [:a, :b], 0, &(&1 + 1))
      {:ok, %{a: %{b: 1}}}

      iex> PathMap.update_auto(%{a: %{b: 2}}, [:a, :b], 0, &(&1 + 1))
      {:ok, %{a: %{b: 3}}}

      iex> PathMap.update_auto(%{a: 1}, [:a, :b], 0, & &1)
      {:error, {:not_a_map, 1, [:a]}}
  """
  @spec update_auto(t(), path(), val(), (val() -> val())) ::
          {:ok, t()} | err_not_a_map() | err_invalid_path() | err_invalid_fun()
  def update_auto(map, path, default, function) do
    cond do
      not is_map(map) -> {:error, {:not_a_map, map, []}}
      not is_list(path) -> {:error, :invalid_path}
      not is_function(function, 1) -> {:error, {:invalid_function, function, 1}}
      true -> update_auto_nested(map, path, default, function, [])
    end
  end

  defp update_auto_nested(map, [], _default, function, _acc) when is_map(map),
    do: {:ok, function.(map)}

  defp update_auto_nested(map, [key], default, function, _acc) when is_map(map) do
    next = Map.get(map, key, default)
    {:ok, Map.put(map, key, function.(next))}
  end

  defp update_auto_nested(map, [key | rest], default, function, acc) when is_map(map) do
    next = Map.get(map, key, %{})

    case update_auto_nested(next, rest, default, function, [key | acc]) do
      {:ok, updated_next} -> {:ok, Map.put(map, key, updated_next)}
      {:error, _} = error -> error
    end
  end

  defp update_auto_nested(not_a_map, _path, _default, _function, acc),
    do: {:error, {:not_a_map, not_a_map, Enum.reverse(acc)}}

  #!SECTION - Write API
end
