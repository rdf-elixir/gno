defmodule Gno.Changeset.HelperTest do
  use GnoCase

  alias Gno.Changeset.Helper

  describe "inserts/1" do
    test "combines add, update, and replace graphs" do
      changeset = %{
        add: graph([1]),
        update: graph([2]),
        replace: graph([3])
      }

      assert Helper.inserts(changeset) == graph([1, 2, 3])
    end

    test "handles nil values" do
      changeset = %{
        add: graph([1]),
        update: nil,
        replace: graph([3])
      }

      assert Helper.inserts(changeset) == graph([1, 3])
    end

    test "returns empty graph when all values are nil" do
      assert Helper.inserts(%{add: nil, update: nil, replace: nil}) == RDF.Graph.new()
    end
  end

  describe "removals/1" do
    test "returns remove graph" do
      changeset = %{remove: graph([1])}

      assert Helper.removals(changeset) == changeset.remove
    end

    test "returns empty graph when remove is nil" do
      assert Helper.removals(%{remove: nil}) == RDF.Graph.new()
    end
  end

  describe "overwrites/1" do
    test "returns overwrite graph" do
      changeset = %{overwrite: graph([1])}

      assert Helper.overwrites(changeset) == changeset.overwrite
    end

    test "returns empty graph when overwrite is nil" do
      changeset = %{overwrite: nil}

      assert Helper.overwrites(changeset) == RDF.Graph.new()
    end

    test "returns empty graph when overwrite key is missing" do
      changeset = %{}

      assert Helper.overwrites(changeset) == RDF.Graph.new()
    end
  end
end
