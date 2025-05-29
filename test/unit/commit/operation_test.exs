defmodule Gno.CommitOperationTest do
  use GnoCase

  doctest Gno.CommitOperation

  alias Gno.{CommitOperation, EffectiveChangeset}
  alias Gno.Commit.Processor

  describe "new/0" do
    test "creates a new commit operation with default values" do
      assert {:ok, %CommitOperation{__id__: %BlankNode{}, middlewares: []}} =
               CommitOperation.new()
    end

    test "with middlewares as classes" do
      assert {:ok,
              %CommitOperation{
                middlewares: [%Gno.CommitLogger{}, %TestStateFlowMiddleware{}]
              }} =
               CommitOperation.new(middlewares: [Gno.CommitLogger, EX.TestStateFlowMiddleware])
    end
  end

  describe "init/1" do
    test "initializes with an EffectiveChangeset" do
      changeset = EffectiveChangeset.new!(add: EX.S |> EX.p(EX.O))

      assert {:ok, %Processor{changeset: ^changeset}} =
               %{commit_processor() | input: changeset}
               |> CommitOperation.init()
    end

    test "initializes with a Changeset" do
      changeset = Changeset.new!(add: EX.S |> EX.p(EX.O))

      assert {:ok, %Processor{changeset: %Changeset{}}} =
               %{commit_processor() | input: changeset}
               |> CommitOperation.init()
    end

    test "initializes with changeset args" do
      changes = [add: EX.S |> EX.p(EX.O)]

      assert {:ok, %Processor{changeset: %Changeset{}}} =
               %{commit_processor() | input: changes}
               |> CommitOperation.init()
    end

    test "initializes with a commit_id" do
      changes = [add: EX.S |> EX.p(EX.O)]

      assert {:ok, %Processor{commit_id: commit_id}} =
               %{commit_processor() | input: changes}
               |> CommitOperation.init()

      assert %RDF.BlankNode{} = commit_id
    end
  end
end
