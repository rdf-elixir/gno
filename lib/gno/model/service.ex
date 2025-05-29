defmodule Gno.Service do
  use Grax.Schema

  alias Gno.Store
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
  def handle_sparql(
        operation,
        %{store: store, repository: %repository_type{} = repository},
        graph,
        opts \\ []
      ) do
    Store.handle_sparql(operation, store, repository_type.graph_id(repository, graph), opts)
  end
end
