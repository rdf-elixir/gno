defmodule Gno.Service do
  use Grax.Schema

  alias Gno.Store
  alias Gno.CommitOperation

  schema Gno.Service do
    link repository: Gno.serviceRepository(), type: Gno.Repository, required: true
    link store: Gno.serviceStore(), type: Gno.Store, required: true
    link commit_operation: Gno.serviceCommitOperation(), type: Gno.CommitOperation
  end

  # We do not rely on getting concrete structs here, but accept any Grax schema that subclasses
  def handle_sparql(
        operation,
        %{store: store, repository: %repository_type{} = repository},
        graph,
        opts \\ []
      ) do
    Store.handle_sparql(operation, store, repository_type.graph_id(repository, graph), opts)
  end

  @doc false
  def on_load(%{commit_operation: nil} = service, _graph, _opts) do
    {:ok, %__MODULE__{service | commit_operation: CommitOperation.default()}}
  end

  def on_load(service, _graph, _opts) do
    with {:ok, operation} <- resolve_commit_operation(service.commit_operation) do
      {:ok, %{service | commit_operation: operation}}
    end
  end

  defp resolve_commit_operation(%CommitOperation{} = commit_operation) do
    if commit_operation_type = CommitOperation.type(commit_operation.__id__) do
      {:ok, commit_operation_type.default()}
    else
      {:ok, commit_operation}
    end
  end

  defp resolve_commit_operation(commit_operation), do: {:ok, commit_operation}
end
