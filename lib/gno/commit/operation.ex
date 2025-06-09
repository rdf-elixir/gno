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

  @preliminary_commit_id RDF.bnode(:preliminary_commit_id)

  @rollback_update_states [
    :changes_applied,
    :ending_transaction
  ]

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
  def all_changes(processor) do
    Map.put(processor.additional_changes, :dataset, processor.effective_changeset)
  end

  @impl true
  def handle_step(:init, processor) do
    with {:ok, changeset} <- init_changeset(processor.input) do
      {:ok,
       %Processor{processor | changeset: changeset}
       |> Processor.set_commit_id(@preliminary_commit_id, false)}
    end
  end

  @impl true
  def handle_step(:preparation, processor) do
    with {:ok, effective_changeset} <-
           Gno.EffectiveChangeset.Query.call(processor.service, processor.changeset) do
      %Processor{processor | effective_changeset: effective_changeset}
      |> Processor.operation_type(processor).prepare_commit()
    end
  end

  @impl true
  def handle_step(:apply_changes, processor) do
    with {:ok, update} <-
           Update.build(processor.service.repository, Processor.all_changes(processor)),
         :ok <- Service.handle_sparql(update, processor.service) do
      {:ok, %Processor{processor | sparql_update: update}}
    end
  end

  @impl true
  def handle_step(_step, processor), do: {:ok, processor}

  @impl true
  def handle_empty_changeset(_processor, "error", changeset), do: {:error, changeset}
  def handle_empty_changeset(processor, "skip", _changeset), do: {:skip_transaction, processor}

  def handle_empty_changeset(processor, "proceed", _changeset) do
    {:ok, %Processor{processor | effective_changeset: EffectiveChangeset.empty()}}
  end

  def handle_empty_changeset(_processor, invalid, _changeset),
    do: {:error, "Invalid on_no_effective_changes value: #{invalid}"}

  @impl true
  def prepare_commit(%Processor{effective_changeset: %EffectiveChangeset{}} = processor) do
    with {:ok, commit} <- Commit.new(processor.effective_changeset) do
      processor
      |> Processor.set_commit_id(commit.__id__)
      |> Processor.update_metadata(&Graph.put_properties(Grax.to_rdf!(commit), &1))
    end
  end

  def prepare_commit(processor), do: {:ok, processor}

  # This current naive_metadata_rollback version is not safe, as the additional_changes are not effective changes.
  @impl true
  def rollback(state, processor) when state in @rollback_update_states do
    with {:ok, update} <-
           Update.build_revert(processor.service.repository, Processor.all_changes(processor)),
         :ok <- Service.handle_sparql(update, processor.service) do
      {:ok, processor}
    end
  end

  @impl true
  def rollback(_state, processor), do: {:ok, processor}

  defp init_changeset(%EffectiveChangeset{} = changeset), do: {:ok, changeset}
  defp init_changeset(changes), do: Changeset.new(changes)

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

      iex> Gno.CommitOperation.type?(Gno.CommitLogger)
      false

      iex> Gno.CommitOperation.type?(NonExisting)
      false

  """
  @spec type?(module) :: boolean
  def type?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :handle_step, 2)
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
