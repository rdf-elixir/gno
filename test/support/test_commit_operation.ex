defmodule TestCommitOperation do
  @moduledoc """
  A test implementation of a custom CommitOperation for testing purposes.
  """

  use Gno.CommitOperation.Type

  alias Gno.Commit.Processor
  alias RDF.Graph
  alias Gno.TestNamespaces.EX
  @compile {:no_warn_undefined, Gno.TestNamespaces.EX}

  import Gno.TestFactories

  def_commit_operation EX.TestCommitOperation do
    property custom_property: EX.customProperty(),
             type: :string,
             default: "test"
  end

  @commit_id EX.customCommitId()

  @impl true
  def all_changes(processor) do
    processor
    |> super()
    |> Processor.add_additional_changes(:repo,
      add: RDF.graph(@commit_id |> EX.customMetadata("test"))
    )
  end

  @impl true
  def handle_step(:init, processor) do
    with {:ok, processor} <- super(:init, processor) do
      {:ok,
       processor
       |> Processor.set_commit_id(@commit_id, false)
       |> Processor.assign(:custom_init, true)}
    end
  end

  @impl true
  def handle_step(step, processor), do: super(step, processor)

  @impl true
  def prepare_commit(processor) do
    processor
    |> Processor.set_commit_id(@commit_id)
    |> Processor.update_metadata(fn metadata ->
      Graph.put_properties(
        metadata,
        @commit_id
        |> EX.customMetadata("test")
        |> PROV.endedAtTime(test_time())
      )
    end)
  end

  def test_time, do: datetime()

  @impl true
  def result(processor) do
    Gno.CommitOperation.result(processor)
  end
end
