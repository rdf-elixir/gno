defmodule TestCommitOperation do
  @moduledoc """
  A test implementation of a custom CommitOperation for testing purposes.
  """

  @behaviour Gno.CommitOperation.Type
  use Grax.Schema

  alias Gno.Commit.Processor
  alias RDF.Graph
  alias Gno.TestNamespaces.EX
  @compile {:no_warn_undefined, Gno.TestNamespaces.EX}

  import Gno.TestFactories

  schema EX.TestCommitOperation < Gno.CommitOperation do
    property custom_property: EX.customProperty(),
             type: :string,
             default: "test"
  end

  @impl true
  def new(id, args \\ []) do
    build(id, args)
  end

  def new!(id, args \\ []), do: Gno.Utils.bang!(&new/2, [id, args])

  @impl true
  def default do
    case new(RDF.bnode("test-custom-commit-operation"), custom_property: "default-test") do
      {:ok, operation} -> operation
      {:error, error} -> raise error
    end
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
    with {:ok, commit} <- Gno.CommitOperation.result(processor) do
      {:ok, Processor.assign(processor, :commit, commit)}
    end
  end
end
