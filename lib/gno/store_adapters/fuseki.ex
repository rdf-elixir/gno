defmodule Gno.Store.Adapters.Fuseki do
  use Grax.Schema

  alias Gno.NS.GnoA

  schema GnoA.Fuseki < Gno.Store do
    # overrides the port default value
    property port: Gno.storeEndpointPort(), type: :integer, default: 3030
    property dataset: Gno.storeEndpointDataset(), type: :string, required: true

    property query_endpoint: Gno.storeQueryEndpoint(), type: :iri, required: false
    property update_endpoint: Gno.storeUpdateEndpoint(), type: :iri, required: false
    property graph_store_endpoint: Gno.storeGraphStoreEndpoint(), type: :iri, required: false
  end

  # we need to define this after the Grax schema to be able to use %__MODULE__{} in the macro
  use Gno.Store.Adapter,
    name: :fuseki,
    query_endpoint_path: "query",
    update_endpoint_path: "update",
    graph_store_endpoint_path: "data"
end
