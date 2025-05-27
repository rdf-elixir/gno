defmodule Gno.CommitOperationTest do
  use GnoCase

  doctest Gno.CommitOperation

  alias Gno.{CommitOperation, EffectiveChangeset}
  alias Gno.Commit.Processor

  describe "default/0" do
    test "returns a default CommitOperation" do
      assert %CommitOperation{__id__: %BlankNode{}, middlewares: []} = CommitOperation.default()
    end
  end

  describe "init/1" do
    setup do
      %{processor: Processor.new!(Manifest.service!())}
    end

    test "initializes with an EffectiveChangeset", %{processor: processor} do
      changeset = EffectiveChangeset.new!(add: EX.S |> EX.p(EX.O))

      assert {:ok, %Processor{changeset: ^changeset}} =
               %{processor | input: changeset}
               |> CommitOperation.init()
    end

    test "initializes with a Changeset", %{processor: processor} do
      changeset = Changeset.new!(add: EX.S |> EX.p(EX.O))

      assert {:ok, %Processor{changeset: %Changeset{}}} =
               %{processor | input: changeset}
               |> CommitOperation.init()
    end

    test "initializes with changeset args", %{processor: processor} do
      changes = [add: EX.S |> EX.p(EX.O)]

      assert {:ok, %Processor{changeset: %Changeset{}}} =
               %{processor | input: changes}
               |> CommitOperation.init()
    end

    test "initializes with a commit_id", %{processor: processor} do
      changes = [add: EX.S |> EX.p(EX.O)]

      assert {:ok, %Processor{commit_id: commit_id}} =
               %{processor | input: changes}
               |> CommitOperation.init()

      assert %RDF.BlankNode{} = commit_id
    end
  end
end
