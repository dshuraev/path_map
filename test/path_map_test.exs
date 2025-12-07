defmodule PathMapTest do
  use ExUnit.Case
  doctest PathMap

  describe "fetch/2" do
    test "returns value when path exists" do
      assert {:ok, 1} == PathMap.fetch(%{a: %{b: 1}}, [:a, :b])
    end

    test "returns full map when path is empty" do
      assert {:ok, %{a: 1}} == PathMap.fetch(%{a: 1}, [])
    end

    test "errors when map is not a map (takes precedence over invalid path)" do
      assert {:error, {:not_a_map, :oops, []}} == PathMap.fetch(:oops, :bad_path)
    end

    test "errors on invalid path type" do
      assert {:error, :invalid_path} == PathMap.fetch(%{}, :bad)
    end

    test "errors when key is missing" do
      assert {:error, {:missing, [:a]}} == PathMap.fetch(%{}, [:a])
    end

    test "errors when intermediate segment is missing" do
      assert {:error, {:missing, [:a]}} == PathMap.fetch(%{}, [:a, :b])
    end

    test "errors when encountering non-map intermediate" do
      assert {:error, {:not_a_map, 1, [:a]}} == PathMap.fetch(%{a: 1}, [:a, :b])
    end
  end

  describe "get/3" do
    test "returns found value" do
      assert 2 == PathMap.get(%{a: 2}, [:a], :default)
    end

    test "uses nil default when not provided" do
      assert nil == PathMap.get(%{}, [:missing])
    end

    test "returns default on any error" do
      assert :default == PathMap.get(:oops, [:a], :default)
      assert :default == PathMap.get(%{}, :bad_path, :default)
    end
  end

  describe "exists?/2" do
    test "returns true when path exists" do
      assert PathMap.exists?(%{a: %{b: 1}}, [:a, :b])
    end

    test "returns false for missing or invalid paths" do
      refute PathMap.exists?(%{}, [:a])
      refute PathMap.exists?(%{}, :bad_path)
    end
  end

  describe "validate_path/2 and valid_path?/2" do
    test "succeeds on existing path" do
      assert :ok == PathMap.validate_path(%{a: %{b: 1}}, [:a, :b])
      assert PathMap.valid_path?(%{a: %{b: 1}}, [:a, :b])
    end

    test "returns invalid_path when path type is wrong" do
      assert {:error, :invalid_path} == PathMap.validate_path(%{}, :bad)
      refute PathMap.valid_path?(%{}, :bad)
    end

    test "prioritizes not_a_map over invalid_path" do
      assert {:error, {:not_a_map, :oops, []}} == PathMap.validate_path(:oops, :bad)
      refute PathMap.valid_path?(:oops, :bad)
    end
  end

  describe "put_auto/3" do
    test "replaces the entire map when path is empty" do
      assert {:ok, :new} == PathMap.put_auto(%{a: 1}, [], :new)
    end

    test "inserts single level key" do
      assert {:ok, %{a: 1}} == PathMap.put_auto(%{}, [:a], 1)
    end

    test "auto-vivifies nested path" do
      assert {:ok, %{a: %{b: 2}}} == PathMap.put_auto(%{}, [:a, :b], 2)
    end

    test "errors when encountering non-map intermediate" do
      assert {:error, {:not_a_map, 1, [:a]}} == PathMap.put_auto(%{a: 1}, [:a, :b], 2)
    end

    test "errors when map is not a map" do
      assert {:error, {:not_a_map, :oops, []}} == PathMap.put_auto(:oops, [:a], 1)
    end

    test "errors on invalid path type" do
      assert {:error, :invalid_path} == PathMap.put_auto(%{}, :bad, 1)
    end

    test "propagates nested non-map errors when deeper segment is invalid" do
      map = %{a: %{b: %{c: 1}}}

      assert {:error, {:not_a_map, 1, [:a, :b, :c]}} ==
               PathMap.put_auto(map, [:a, :b, :c, :d], 2)
    end
  end

  describe "put/3" do
    test "updates an existing nested value" do
      map = %{a: %{b: 1}}

      assert {:ok, %{a: %{b: 2}}} == PathMap.put(map, [:a, :b], 2)
    end

    test "errors when encountering non-map intermediate node" do
      assert {:error, {:not_a_map, 1, [:a]}} == PathMap.put(%{a: 1}, [:a, :b], 2)
    end

    test "errors when a path segment is missing" do
      assert {:error, {:missing, [:a]}} == PathMap.put(%{}, [:a, :b], 2)
    end

    test "errors on invalid path type" do
      assert {:error, :invalid_path} == PathMap.put(%{}, :oops, 1)
    end

    test "replaces the entire map when path is empty" do
      assert {:ok, 5} == PathMap.put(%{a: 1}, [], 5)
    end

    test "errors when root is not a map" do
      assert {:error, {:not_a_map, :oops, []}} == PathMap.put(:oops, [:a], 1)
    end
  end

  describe "put_new/3" do
    test "inserts when missing" do
      assert {:ok, %{a: %{b: 1}}} == PathMap.put_new(%{a: %{}}, [:a, :b], 1)
    end

    test "errors when leaf exists" do
      assert {:error, :already_exists} == PathMap.put_new(%{a: %{b: 1}}, [:a, :b], 2)
    end

    test "errors when intermediate missing" do
      assert {:error, {:missing, [:a]}} == PathMap.put_new(%{}, [:a, :b], 1)
    end

    test "errors when root is not a map" do
      assert {:error, {:not_a_map, :oops, []}} == PathMap.put_new(:oops, [:a], 1)
    end

    test "errors when path is invalid" do
      assert {:error, :invalid_path} == PathMap.put_new(%{}, :bad, 1)
    end

    test "errors when path is empty" do
      assert {:error, :already_exists} == PathMap.put_new(%{}, [], 1)
    end

    test "errors when encountering non-map intermediate" do
      assert {:error, {:not_a_map, 1, [:a]}} == PathMap.put_new(%{a: 1}, [:a, :b], 2)
    end
  end

  describe "put_new_auto/3" do
    test "auto-vivifies missing path" do
      assert {:ok, %{a: %{b: %{c: 3}}}} ==
               PathMap.put_new_auto(%{}, [:a, :b, :c], 3)
    end

    test "inserts under existing nested map" do
      assert {:ok, %{a: %{b: %{c: 1}}}} ==
               PathMap.put_new_auto(%{a: %{b: %{}}}, [:a, :b, :c], 1)
    end

    test "errors when leaf exists" do
      assert {:error, :already_exists} ==
               PathMap.put_new_auto(%{a: %{b: 1}}, [:a, :b], 2)
    end

    test "errors when encountering non-map intermediate" do
      assert {:error, {:not_a_map, 1, [:a]}} ==
               PathMap.put_new_auto(%{a: 1}, [:a, :b], 2)
    end

    test "errors when root is not a map" do
      assert {:error, {:not_a_map, :oops, []}} == PathMap.put_new_auto(:oops, [:a], 1)
    end

    test "errors when path is invalid" do
      assert {:error, :invalid_path} == PathMap.put_new_auto(%{}, :bad, 1)
    end

    test "errors when path is empty" do
      assert {:error, :already_exists} == PathMap.put_new_auto(%{}, [], 1)
    end

    test "propagates nested non-map errors during auto-vivification" do
      map = %{a: %{b: %{c: 1}}}

      assert {:error, {:not_a_map, 1, [:a, :b, :c]}} ==
               PathMap.put_new_auto(map, [:a, :b, :c, :d], 2)
    end
  end

  describe "ensure/3" do
    test "leaves existing value untouched" do
      assert {:ok, %{a: 1}} == PathMap.ensure(%{a: 1}, [:a], fn -> 5 end)
    end

    test "initializes missing leaf" do
      assert {:ok, %{a: %{b: 2}}} == PathMap.ensure(%{a: %{}}, [:a, :b], fn -> 2 end)
    end

    test "errors when initializer is invalid" do
      assert {:error, {:invalid_initializer, 123}} == PathMap.ensure(%{}, [:a], 123)
    end

    test "errors when path segment is missing" do
      assert {:error, {:missing, [:a]}} == PathMap.ensure(%{}, [:a, :b], fn -> 1 end)
    end

    test "errors when encountering non-map intermediate" do
      assert {:error, {:not_a_map, 1, [:a]}} ==
               PathMap.ensure(%{a: 1}, [:a, :b], fn -> 1 end)
    end

    test "errors when path type is invalid" do
      assert {:error, :invalid_path} == PathMap.ensure(%{}, :bad, fn -> 1 end)
    end

    test "errors when root is not a map" do
      assert {:error, {:not_a_map, :oops, []}} == PathMap.ensure(:oops, [:a], fn -> 1 end)
    end

    test "is no-op when path is empty" do
      assert {:ok, %{a: 1}} == PathMap.ensure(%{a: 1}, [], fn -> 2 end)
    end
  end

  describe "update/3" do
    test "updates existing value" do
      assert {:ok, %{a: 2}} == PathMap.update(%{a: 1}, [:a], &(&1 + 1))
    end

    test "errors when leaf is missing" do
      assert {:error, :leaf_missing} == PathMap.update(%{a: %{}}, [:a, :b], &(&1 + 1))
    end

    test "errors when intermediate path is missing" do
      assert {:error, {:missing, [:a]}} == PathMap.update(%{}, [:a, :b], &(&1 + 1))
    end

    test "errors when path type is invalid" do
      assert {:error, :invalid_path} == PathMap.update(%{}, :bad, & &1)
    end

    test "errors on invalid function arity" do
      assert {:error, {:invalid_function, :oops, 1}} ==
               PathMap.update(%{a: 1}, [:a], :oops)
    end

    test "errors when root is not a map" do
      assert {:error, {:not_a_map, :oops, []}} == PathMap.update(:oops, [:a], & &1)
    end

    test "errors when encountering non-map intermediate" do
      assert {:error, {:not_a_map, 1, [:a]}} ==
               PathMap.update(%{a: 1}, [:a, :b], & &1)
    end

    test "updates nested existing value" do
      assert {:ok, %{a: %{b: %{c: 2}}}} ==
               PathMap.update(%{a: %{b: %{c: 1}}}, [:a, :b, :c], &(&1 + 1))
    end

    test "applies function when path is empty" do
      assert {:ok, %{a: 1, b: 2}} ==
               PathMap.update(%{a: 1}, [], &Map.put(&1, :b, 2))
    end
  end

  describe "update/4" do
    test "updates existing leaf" do
      assert {:ok, %{a: 2}} == PathMap.update(%{a: 1}, [:a], 0, &(&1 + 1))
    end

    test "sets default when leaf missing" do
      assert {:ok, %{a: %{b: 5}}} ==
               PathMap.update(%{a: %{}}, [:a, :b], 5, &(&1 + 1))
    end

    test "errors when intermediate missing" do
      assert {:error, {:missing, [:a]}} == PathMap.update(%{}, [:a, :b], 0, &(&1 + 1))
    end

    test "errors when root is not a map" do
      assert {:error, {:not_a_map, :oops, []}} == PathMap.update(:oops, [:a], 0, & &1)
    end

    test "errors on invalid function arity" do
      assert {:error, {:invalid_function, :bad, 1}} ==
               PathMap.update(%{a: 1}, [:a], 0, :bad)
    end

    test "errors when encountering non-map intermediate" do
      assert {:error, {:not_a_map, 1, [:a]}} ==
               PathMap.update(%{a: 1}, [:a, :b], 0, & &1)
    end

    test "errors when path type is invalid" do
      assert {:error, :invalid_path} == PathMap.update(%{}, :bad, 0, & &1)
    end

    test "applies function when path is empty" do
      assert {:ok, %{a: 1, b: 3}} ==
               PathMap.update(%{a: 1}, [], %{}, &Map.put(&1, :b, 3))
    end
  end

  describe "update_auto/4" do
    test "auto-vivifies and sets default when missing" do
      assert {:ok, %{a: %{b: %{c: 5}}}} ==
               PathMap.update_auto(%{}, [:a, :b, :c], 5, & &1)
    end

    test "updates existing value" do
      assert {:ok, %{a: %{b: 3}}} ==
               PathMap.update_auto(%{a: %{b: 2}}, [:a, :b], 0, &(&1 + 1))
    end

    test "errors when encountering non-map intermediate" do
      assert {:error, {:not_a_map, 1, [:a]}} ==
               PathMap.update_auto(%{a: 1}, [:a, :b], 0, & &1)
    end

    test "errors when root is not a map" do
      assert {:error, {:not_a_map, :oops, []}} == PathMap.update_auto(:oops, [:a], 0, & &1)
    end

    test "errors on invalid path type" do
      assert {:error, :invalid_path} == PathMap.update_auto(%{}, :bad, 0, & &1)
    end

    test "errors on invalid function arity" do
      assert {:error, {:invalid_function, :bad, 1}} ==
               PathMap.update_auto(%{}, [:a], 0, :bad)
    end

    test "propagates nested non-map errors when encountered deeper" do
      map = %{a: %{b: %{c: 1}}}

      assert {:error, {:not_a_map, 1, [:a, :b, :c]}} ==
               PathMap.update_auto(map, [:a, :b, :c, :d], 0, & &1)
    end

    test "applies function when path is empty" do
      assert {:ok, %{a: 1}} ==
               PathMap.update_auto(%{a: 1}, [], %{}, &Map.put(&1, :a, 1))
    end
  end
end
