defmodule Gno.Service do
  use Grax.Schema

  alias Gno.Store
  alias Gno.Store.SPARQL.Operation
  alias Gno.CommitOperation

  import Gno.Utils, only: [bang!: 2]

  schema Gno.Service do
    link repository: Gno.serviceRepository(), type: Gno.Repository, required: true
    link store: Gno.serviceStore(), type: Gno.Store, required: true
    link commit_operation: Gno.serviceCommitOperation(), type: Gno.CommitOperation
  end

  @default_commit_operation_id RDF.bnode("commit-operation")

  def new(attrs \\ []) do
    {id, attrs} = Keyword.pop(attrs, :id, RDF.bnode())
    build(id, attrs)
  end

  def new!(attrs \\ []), do: bang!(&new/1, [attrs])

  def build(id, attrs \\ []) do
    with {:ok, service} <- super(id, attrs) do
      init_commit_operation(service)
    end
  end

  def build!(id, attrs \\ []), do: bang!(&build/2, [id, attrs])

  @doc false
  def on_load(service, _graph, _opts) do
    init_commit_operation(service)
  end

  @doc false
  def init_commit_operation(%service_type{} = service, id \\ @default_commit_operation_id) do
    {:resource, commit_operation_type} = service_type.__property__(:commit_operation).type

    with {:ok, commit_operation} <-
           normalize_commit_operation(service.commit_operation, commit_operation_type, id) do
      {:ok, %{service | commit_operation: commit_operation}}
    end
  end

  @doc false
  def default_commit_operation(type \\ Gno.CommitOperation, id \\ @default_commit_operation_id) do
    case type.build(id) do
      {:ok, operation} -> operation
      {:error, error} -> raise error
    end
  end

  defp normalize_commit_operation(nil, type, id), do: {:ok, default_commit_operation(type, id)}

  defp normalize_commit_operation(%RDF.IRI{} = commit_type, _type, id) do
    if commit_operation_type = CommitOperation.type(commit_type) do
      {:ok, default_commit_operation(commit_operation_type, id)}
    else
      {:error, "invalid commit operation type: #{inspect(commit_type)}"}
    end
  end

  # if we specify just a commit operation class, this results in a commit operation
  # - with the type specified on the service schema (not a subclass)
  # - with the id of a commit operation class
  defp normalize_commit_operation(%type{} = commit_operation, type, id) do
    if commit_operation_type = CommitOperation.type(commit_operation.__id__) do
      {:ok, default_commit_operation(commit_operation_type, id)}
    else
      {:ok, commit_operation}
    end
  end

  defp normalize_commit_operation(commit_operation, _type, _id), do: {:ok, commit_operation}

  # We do not rely on getting concrete structs here, but accept any Grax schema that subclasses
  def handle_sparql(operation, %{store: store} = service, opts \\ []) do
    {graph, opts} = Keyword.pop(opts, :graph, default_graph(operation))

    operation
    |> resolve_operation_graphs(service)
    |> Store.handle_sparql(store, graph_name(service, graph, operation.name), opts)
  end

  # Unfortunately, SPARQL UPDATE queries cannot be executed on a specific graph by default
  defp default_graph(%Operation{type: :update, update_type: :query}), do: nil
  defp default_graph(_), do: :dataset

  defp graph_name(%service_type{} = service, :service, operation_name)
       when operation_name in [:create, :drop, :clear] do
    service_type.graphs(service)
  end

  defp graph_name(%_service_type{repository: %repository_type{} = repository}, graph, _) do
    repository_type.graph_name(repository, graph)
  end

  defp resolve_operation_graphs(
         %Operation{name: name, payload: [from: from, to: to]} = operation,
         service
       )
       when name in [:add, :copy, :move] do
    %{
      operation
      | payload: [from: graph_name(service, from, name), to: graph_name(service, to, name)]
    }
  end

  defp resolve_operation_graphs(operation, _repository), do: operation

  def graphs(%_service_type{repository: %repository_type{} = repository}) do
    repository_type.graphs(repository)
  end

  @doc """
  Checks if the service's repository exists in its store.
  """
  @spec check_setup(t()) :: :ok | {:error, term()}
  def check_setup(%service_type{} = service) do
    """
    #{RDF.prefix_map(gno: Gno) |> RDF.PrefixMap.to_sparql()}
    ASK {
      <#{service.repository.__id__}> gno:repositoryDataset ?dataset .
    }
    """
    |> Operation.ask!()
    |> service_type.handle_sparql(service, graph: :repo)
    |> case do
      {:ok, %SPARQL.Query.Result{results: true}} -> :ok
      {:ok, %SPARQL.Query.Result{results: false}} -> {:error, :repository_not_found}
      {:error, reason} -> {:error, {:query_failed, reason}}
    end
  end

  @doc """
  Validates basic setup integrity.
  """
  @spec validate_setup(t()) :: :ok | {:error, term()}
  def validate_setup(%service_type{} = service) do
    """
    #{RDF.prefix_map(gno: Gno) |> RDF.PrefixMap.to_sparql()}
    ASK {
      <#{service.repository.__id__}> gno:repositoryDataset ?dataset .
      ?dataset a gno:Dataset .
    }
    """
    |> Operation.ask!()
    |> service_type.handle_sparql(service, graph: :repo)
    |> case do
      {:ok, %SPARQL.Query.Result{results: true}} -> :ok
      {:ok, %SPARQL.Query.Result{results: false}} -> {:error, :invalid_repository_structure}
      {:error, reason} -> {:error, {:query_failed, reason}}
    end
  end
end
