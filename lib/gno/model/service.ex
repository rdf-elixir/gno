defmodule Gno.Service do
  use Grax.Schema

  alias Gno.Store

  schema Gno.Service do
    link repository: Gno.serviceRepository(), type: Gno.Repository, required: true
    link store: Gno.serviceStore(), type: Gno.Store, required: true
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
end
