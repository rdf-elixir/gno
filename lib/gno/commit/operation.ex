defmodule Gno.CommitOperation do
  use Grax.Schema

  alias Gno.{Commit, Changeset, EffectiveChangeset, CommitMiddleware}
  alias Gno.Commit.Processor
  alias RDF.Graph

  import Gno.Utils, only: [bang!: 2]
  import RDF.Utils

  schema Gno.CommitOperation do
    link middlewares: Gno.commitMiddleware(), type: ordered_list_of(CommitMiddleware)
  end

  @behaviour Gno.CommitOperation.Type

  @impl true
  def new(id, args \\ []) do
    build(id, args)
  end

  def new!(id, args \\ []), do: bang!(&new/2, [id, args])

  @impl true
  def default() do
    case new(RDF.bnode("commit-operation")) do
      {:ok, operation} -> operation
      {:error, error} -> raise error
    end
  end

  @impl true
  def init(processor) do
    with {:ok, changeset} <- init_changeset(processor.input_changes) do
      {:ok, %Processor{processor | changeset: changeset, commit_id: init_commit_id()}}
    end
  end

  defp init_commit_id(), do: RDF.bnode()

  defp init_changeset(%EffectiveChangeset{} = changeset), do: {:ok, changeset}
  defp init_changeset(changes), do: Changeset.new(changes)

  @impl true
  def commit_id(processor) do
    processor.commit_id
  end

  @impl true
  def add_metadata(processor) do
    Processor.update_metadata(processor, fn metadata ->
      Graph.add(metadata, Processor.commit_id(processor) |> PROV.endedAtTime(DateTime.utc_now()))
    end)
  end

  @impl true
  def result(processor) do
    with {:ok, commit} <- Commit.load(processor.metadata, Processor.commit_id(processor)) do
      Grax.put(commit, :changeset, processor.effective_changeset)
    end
  end

  @doc false
  def on_load(operation, _graph, _opts) do
    with {:ok, middlewares} <- map_while_ok(operation.middlewares, &resolve_middleware/1) do
      {:ok, %{operation | middlewares: middlewares}}
    end
  end

  defp resolve_middleware(%CommitMiddleware{} = middleware) do
    if middleware_type = CommitMiddleware.type(middleware.__id__) do
      middleware_type.new()
    else
      {:error, "invalid commit middleware: #{inspect(middleware)}"}
    end
  end

  defp resolve_middleware(middleware), do: {:ok, middleware}

  @doc """
  Checks if the given `module` is a `Gno.CommitOperation.Type`.

  ## Example

      iex> Gno.CommitOperation.type?(Gno.CommitOperation)
      true

      iex> Gno.CommitOperation.type?(Gno.Commit)
      false

      iex> Gno.CommitOperation.type?(NonExisting)
      false

  """
  @spec type?(module) :: boolean
  def type?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :add_metadata, 1)
  end

  def type?(%RDF.IRI{} = iri), do: iri |> Grax.schema() |> type?()
  def type?(_), do: false

  def type(%RDF.IRI{} = iri) do
    schema = Grax.schema(iri)

    if type?(schema) do
      schema
    end
  end

  def type(_), do: nil
end
