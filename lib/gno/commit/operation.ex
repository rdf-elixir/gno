defmodule Gno.CommitOperation do
  use Grax.Schema

  alias Gno.{Commit, Changeset, EffectiveChangeset, CommitMiddleware, Service}
  alias Gno.Commit.{Processor, Update}
  alias RDF.Graph

  import Gno.Utils, only: [bang!: 2]
  import RDF.Utils

  schema Gno.CommitOperation do
    link middlewares: Gno.commitMiddleware(), type: ordered_list_of(CommitMiddleware)

    property on_no_effective_changes: Gno.commitNoEffectiveChangesetHandling(),
             type: :string,
             default: Application.compile_env(:gno, :commit_on_no_effective_changes, "error")
  end

  @behaviour Gno.CommitOperation.Type

  def new(attrs \\ []) do
    {id, attrs} = Keyword.pop(attrs, :id, RDF.bnode())
    build(id, attrs)
  end

  def new!(attrs \\ []), do: bang!(&new/1, [attrs])

  def build(id, attrs \\ []) do
    with {:ok, commit_operation} <- super(id, attrs) do
      init_middlewares(commit_operation)
    end
  end

  @doc false
  def on_load(commit_operation, _graph, _opts) do
    init_middlewares(commit_operation)
  end

  @doc false
  def init_middlewares(commit_operation) do
    with {:ok, middlewares} <- map_while_ok(commit_operation.middlewares, &init_middleware/1) do
      {:ok, %{commit_operation | middlewares: middlewares}}
    end
  end

  defp init_middleware(%RDF.IRI{} = middleware_class) do
    if middleware_type = CommitMiddleware.type(middleware_class) do
      middleware_type.new()
    else
      {:error, "invalid commit middleware: #{inspect(middleware_class)}"}
    end
  end

  defp init_middleware(%CommitMiddleware{} = commit_operation) do
    init_middleware(commit_operation.__id__)
  end

  defp init_middleware(middleware), do: {:ok, middleware}

  @impl true
  def init(processor) do
    with {:ok, changeset} <- init_changeset(processor.input) do
      {:ok, %Processor{processor | changeset: changeset, commit_id: init_commit_id()}}
    end
  end

  defp init_commit_id(), do: RDF.iri(Uniq.UUID.uuid4(:urn))

  defp init_changeset(%EffectiveChangeset{} = changeset), do: {:ok, changeset}
  defp init_changeset(changes), do: Changeset.new(changes)

  @impl true
  def handle_empty_changeset(_processor, "error", changeset), do: {:error, changeset}
  def handle_empty_changeset(processor, "skip", _changeset), do: {:skip_transaction, processor}

  def handle_empty_changeset(processor, "proceed", _changeset) do
    {:ok, %Processor{processor | effective_changeset: EffectiveChangeset.empty()}}
  end

  def handle_empty_changeset(_processor, invalid, _changeset),
    do: {:error, "Invalid on_no_effective_changes value: #{invalid}"}

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
  def prepare_effective_changeset(processor) do
    with {:ok, effective_changeset} <-
           Gno.EffectiveChangeset.Query.call(processor.service, processor.changeset) do
      {:ok, %Processor{processor | effective_changeset: effective_changeset}}
    end
  end

  @impl true
  def apply_changes(processor) do
    with {:ok, update} <-
           Update.build(
             processor.service.repository,
             Map.put(processor.additional_changes, :dataset, processor.effective_changeset)
           ),
         :ok <- Service.handle_sparql(update, processor.service, nil) do
      {:ok, %Processor{processor | sparql_update: update}}
    end
  end

  # This current naive_metadata_rollback version is not safe, as the additional_changes are not effective changes.
  @impl true
  def rollback_changes(processor, _state) do
    with {:ok, update} <-
           Update.build_revert(
             processor.service.repository,
             Map.put(processor.additional_changes, :dataset, processor.effective_changeset)
           ),
         :ok <- Service.handle_sparql(update, processor.service, nil) do
      {:ok, processor}
    end
  end

  @impl true
  def result(%Processor{effective_changeset: %Gno.NoEffectiveChanges{} = changeset} = processor) do
    {:ok, changeset, processor}
  end

  def result(processor) do
    with {:ok, commit} <- Commit.load(processor.metadata, Processor.commit_id(processor)),
         {:ok, commit} <- Grax.put(commit, :changeset, processor.effective_changeset) do
      {:ok, commit, processor}
    end
  end

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
