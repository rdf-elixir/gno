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

  @impl true
  def init(processor) do
    with {:ok, processor} <- Gno.CommitOperation.init(processor) do
      {:ok, Processor.assign(processor, :custom_init, true)}
    end
  end

  @impl true
  def commit_id(_processor) do
    EX.customCommitId()
  end

  @impl true
  def add_metadata(processor) do
    Processor.update_metadata(processor, fn metadata ->
      Graph.put_properties(
        metadata,
        commit_id(processor) |> EX.customMetadata("test") |> PROV.endedAtTime(test_time())
      )
    end)
  end

  def test_time, do: datetime()

  @impl true
  def result(processor) do
    Gno.CommitOperation.result(processor)
  end
end
