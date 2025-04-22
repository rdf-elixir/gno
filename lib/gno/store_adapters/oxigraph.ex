defmodule Gno.Store.Adapters.Oxigraph do
  use Grax.Schema

  alias Gno.NS.GnoA

  schema GnoA.Oxigraph < Gno.Store do
    # overrides the port default value
    property port: Gno.storeEndpointPort(), type: :integer, default: 7878

    property query_endpoint: Gno.storeQueryEndpoint(), type: :iri, required: false
    property update_endpoint: Gno.storeUpdateEndpoint(), type: :iri, required: false
    property graph_store_endpoint: Gno.storeGraphStoreEndpoint(), type: :iri, required: false
  end

  # we need to define this after the Grax schema to be able to use %__MODULE__{} in the macro
  use Gno.Store.Adapter,
    name: :oxigraph,
    query_endpoint_path: "query",
    update_endpoint_path: "update",
    graph_store_endpoint_path: "store"
end
