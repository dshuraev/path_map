defmodule PathMap do
  @moduledoc """
  Documentation for `PathMap`.
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
  @type err_invalid_path :: {:error, {:invalid_path, term()}}
  @type err_invalid_fun :: {:error, {:invalid_function, term(), arity :: non_neg_integer()}}
  @type err_invalid_initializer :: {:error, {:invalid_initializer, term()}}

  # SECTION - Read API
  @doc """
  Fetches a value from `map` at the location specified by `path`.

  Returns `{:ok, val}` on success.

  Errors:
  - `{:error, {:invalid_path, provided}}` if `path` is not a list of keys, `map` can be anything.
  - `{:error, {:missing, prefix}}` if `prefix` does not exist
  - `{:error, {:not_a_map, val, prefix}}` if an intermediate subtree at `prefix` is not a map; `val` is the value at prefix

  here `prefix :: list(key()) ⊆ path`

  Special/edge cases:
  - `path == []` returns `{:ok, original_map}`
  - `fetch(not_map, [])` returns `{:error, {:not_a_map, not_map, []}}`
  """
  @spec fetch(t(), path()) ::
          {:error, {:not_a_map, val(), path()} | {:missing, path()} | {:invalid_path, term()}}
          | {:ok, val()}

  def fetch(map, path) do
    cond do
      not is_map(map) -> {:error, {:not_a_map, map, []}}
      not is_list(path) -> {:error, {:invalid_path, path}}
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
  Get a value from `map` by its `path`. On error, returns `default` value.

  Note that unlike `Map.get/3`, `get/3` will return default value on *any* error,
  e.g. `map` is not a map or `path` is not a list.
  """
  @spec get(t(), path(), default) :: val() | default when default: term()
  def get(map, path, default \\ nil) do
    case fetch(map, path) do
      {:ok, val} -> val
      {:error, _} -> default
    end
  end

  @doc """
  Check if a given `path` exists in `map`.
  Returns `true` if the path is valid and leads to a map value,
  otherwise (on any error) returns `false`.
  """
  @spec exists?(t(), path()) :: boolean()
  def exists?(map, path) do
    case fetch(map, path) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Validate a given `path` of `map`.

  This is a thin wrapper around `fetch/2` that returns `:ok` on success or the
  same error tuple that `fetch/2` would return.
  """
  @spec validate_path(t(), path()) ::
          :ok
          | {:error,
             {:not_a_map, val(), path()} | {:missing, path()} | {:invalid_path, term()}}
  def validate_path(map, path) do
    case fetch(map, path) do
      {:ok, _} -> :ok
      e -> e
    end
  end

  @doc """
  Boolean version of `validate_path/2`.

  Returns `true` when the path can be traversed, `false` otherwise.
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
  Put `val` at `path` into `map`, auto-vivifying intermediate maps.

  Errors:
  - `{:error, {:invalid_path, provided}}` if `path` is not a list
  - `{:error, {:not_a_map, val, prefix}}` if an intermediate subtree at `prefix` is not a map
  """
  @spec put_auto(t(), path(), val()) ::
          {:ok, t()}
          | {:error, {:invalid_path, term()} | {:not_a_map, val(), path()}}
  def put_auto(map, path, val) do
    cond do
      not is_map(map) -> {:error, {:not_a_map, map, []}}
      not is_list(path) -> {:error, {:invalid_path, path}}
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

  Errors:
  - `{:error, {:invalid_path, provided}}` if `path` is not a list
  - `{:error, {:not_a_map, val, prefix}}` if the traversal encounters a non-map at `prefix`
  - `{:error, {:missing, prefix}}` if `prefix` in `path` does not exist

  Special cases:
  - `path == []` replaces the entire `map` with `val`
  """
  @spec put(t(), path(), val()) ::
          {:ok, t()}
          | {:error, {:invalid_path, term()} | {:not_a_map, val(), path()} | {:missing, path()}}
  def put(map, path, val) do
    cond do
      not is_map(map) -> {:error, {:not_a_map, map, []}}
      not is_list(path) -> {:error, {:invalid_path, path}}
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
  Put a new element at `path` with `val`.
  If the element exists, returns error.
  Does not auto-vivify paths.
  """
  @spec put_new(t(), path(), val()) ::
          {:ok, t()}
          | err_not_a_map()
          | err_invalid_path()
          | err_missing()
          | {:error, {:already_exists, path()}}
  def put_new(map, path, val) do
    cond do
      not is_map(map) -> {:error, {:not_a_map, map, []}}
      not is_list(path) -> {:error, {:invalid_path, path}}
      true -> put_new_nested(map, path, val, [])
    end
  end

  defp put_new_nested(map, [], _val, _acc) when is_map(map), do: {:error, {:already_exists, []}}

  defp put_new_nested(map, [key], val, acc) when is_map(map) do
    case Map.fetch(map, key) do
      :error -> {:ok, Map.put(map, key, val)}
      {:ok, _} -> {:error, {:already_exists, Enum.reverse(acc, [key])}}
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
  Put a new element at `path` with `val`.
  If the element exists, returns error.
  Auto vivify path with empty dictionary.
  """
  @spec put_new_auto(t(), path(), val()) ::
          {:ok, t()}
          | err_not_a_map()
          | err_invalid_path()
          | {:error, {:already_exists, path()}}
  def put_new_auto(map, path, val) do
    cond do
      not is_map(map) -> {:error, {:not_a_map, map, []}}
      not is_list(path) -> {:error, {:invalid_path, path}}
      true -> put_new_auto_nested(map, path, val, [])
    end
  end

  defp put_new_auto_nested(map, [], _val, _acc) when is_map(map),
    do: {:error, {:already_exists, []}}

  defp put_new_auto_nested(map, [key], val, acc) when is_map(map) do
    case Map.fetch(map, key) do
      :error -> {:ok, Map.put(map, key, val)}
      {:ok, _} -> {:error, {:already_exists, Enum.reverse(acc, [key])}}
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
  when the element already exists.

  Errors:
  - `{:error, {:invalid_path, provided}}` if `path` is not a list
  - `{:error, {:not_a_map, val, prefix}}` if a non-map is encountered on the way
  - `{:error, {:missing, prefix}}` if part of the path does not exist
  - `{:error, {:invalid_initializer, initializer}}` if initializer is not a 0-arity function

  Special cases:
  - `path == []` is a no-op and returns `{:ok, map}`
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
      not is_list(path) -> {:error, {:invalid_path, path}}
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
  If the element does not exist, return error.
  Does not auto-vivify the paths.
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
      not is_list(path) -> {:error, {:invalid_path, path}}
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
  Update an element at `path` with `function`.
  If it does not exist, set it to `default`.
  Does not auto-vivify the paths.
  """
  @spec update(t(), path(), val(), (val() -> val())) ::
          {:ok, t()} | err_not_a_map() | err_invalid_path() | err_missing() | err_invalid_fun()
  def update(map, path, default, function) do
    cond do
      not is_map(map) -> {:error, {:not_a_map, map, []}}
      not is_list(path) -> {:error, {:invalid_path, path}}
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
  Update an element at `path` with `function`.
  If it does not exist, set it to `default`.
  Auto-vivify the path with empty dictionaries if any missing.
  """
  @spec update_auto(t(), path(), val(), (val() -> val())) ::
          {:ok, t()} | err_not_a_map() | err_invalid_path() | err_invalid_fun()
  def update_auto(map, path, default, function) do
    cond do
      not is_map(map) -> {:error, {:not_a_map, map, []}}
      not is_list(path) -> {:error, {:invalid_path, path}}
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
