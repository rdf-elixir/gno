defmodule Gno.Service do
  use DCATR.Service.Type

  alias Gno.Store
  alias Gno.Store.SPARQL.Operation
  alias Gno.CommitOperation

  import Gno.Utils, only: [bang!: 2]
  import RDF.Guards

  schema Gno.Service < DCATR.Service do
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
      {:error, ArgumentError.exception("invalid commit operation type: #{inspect(commit_type)}")}
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
    {graph, opts} = Keyword.pop(opts, :graph, default_graph_for_operation(operation))

    operation
    |> resolve_operation_graphs(service, opts)
    |> Store.handle_sparql(
      store,
      operation_graph_name(service, graph, operation.name, opts),
      opts
    )
  end

  # Unfortunately, SPARQL UPDATE queries cannot be executed on a specific graph by default
  defp default_graph_for_operation(%Operation{type: :update, update_type: :query}), do: nil
  defp default_graph_for_operation(_), do: Gno.default_target_graph()

  @impl true
  def graph_name(service, id_or_selector, opts \\ [])
  def graph_name(_service, :all, _), do: :all
  def graph_name(service, id_or_selector, opts), do: super(service, id_or_selector, opts)

  defp strict_graph_name_mode(opts) do
    Keyword.get(opts, :strict, Application.get_env(:gno, :strict_graph_name, false))
  end

  defp operation_graph_name(service, :service, :create, opts) do
    operation_graph_name(service, :service, :clear, opts) -- [:default]
  end

  defp operation_graph_name(%service_type{} = service, :service, operation_name, opts)
       when operation_name in [:drop, :clear] do
    strict = strict_graph_name_mode(opts)

    service_type.graphs(service)
    |> Enum.map(&service_type.graph_name(service, &1, strict: strict))
    # Graphs with bnodes are not supported by SPARQL and per se only in the manifest
    |> Enum.reject(&is_rdf_bnode/1)
  end

  defp operation_graph_name(%service_type{} = service, graph, _, opts) do
    service_type.graph_name(service, graph, strict: strict_graph_name_mode(opts))
  end

  defp resolve_operation_graphs(
         %Operation{name: name, payload: [from: from, to: to]} = operation,
         service,
         opts
       )
       when name in [:add, :copy, :move] do
    %{
      operation
      | payload: [
          from: operation_graph_name(service, from, name, opts),
          to: operation_graph_name(service, to, name, opts)
        ]
    }
  end

  defp resolve_operation_graphs(operation, _repository, _opts), do: operation

  @doc """
  Checks if the service's repository exists in its store.
  """
  @spec check_setup(t()) :: :ok | {:error, term()}
  def check_setup(%service_type{} = service) do
    """
    #{RDF.prefix_map(dcatr: DCATR) |> RDF.PrefixMap.to_sparql()}
    ASK {
      { <#{service.repository.__id__}> dcatr:repositoryDataset ?x . }
      UNION
      { <#{service.repository.__id__}> dcatr:repositoryDataGraph ?x . }
    }
    """
    |> Operation.ask!()
    |> service_type.handle_sparql(service, graph: :repo_manifest)
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
    #{RDF.prefix_map(dcatr: DCATR) |> RDF.PrefixMap.to_sparql()}
    ASK {
      { <#{service.repository.__id__}> dcatr:repositoryDataset ?x . }
      UNION
      { <#{service.repository.__id__}> dcatr:repositoryDataGraph ?x . }
    }
    """
    |> Operation.ask!()
    |> service_type.handle_sparql(service, graph: :repo_manifest)
    |> case do
      {:ok, %SPARQL.Query.Result{results: true}} -> :ok
      {:ok, %SPARQL.Query.Result{results: false}} -> {:error, :invalid_repository_structure}
      {:error, reason} -> {:error, {:query_failed, reason}}
    end
  end

  @doc false
  @spec with_stored_repository(t(), keyword()) :: {:ok, t()} | {:error, term()}
  def with_stored_repository(%_service_type{} = service, opts \\ []) do
    with {:ok, repository} <- fetch_repository(service, opts) do
      {:ok, %{service | repository: repository}}
    end
  end

  @doc false
  @spec fetch_repository(t(), keyword()) :: {:ok, DCATR.Repository.t()} | {:error, term()}
  def fetch_repository(%_service_type{repository: %repository_type{}} = service, opts \\ []) do
    depth = Keyword.get(opts, :depth, 99)

    with {:ok, graph} <- fetch_repository_graph(service, opts),
         {:ok, repository} <- repository_type.load(graph, service.repository.__id__, depth: depth) do
      {:ok, repository}
    end
  end

  @doc false
  @spec fetch_repository_graph(t(), keyword()) :: {:ok, RDF.Graph.t()} | {:error, term()}
  def fetch_repository_graph(%service_type{} = service, _opts \\ []) do
    service_type.handle_sparql(Gno.QueryUtils.graph_query(), service, graph: :repo_manifest)
  end
end
