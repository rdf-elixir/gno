defmodule Gno.Store.Adapters.Qlever do
  @moduledoc """
  A `Gno.Store.Adapter` implementation for [QLever](https://github.com/ad-freiburg/qlever).

  QLever uses a single root endpoint for all SPARQL operations (query, update,
  and Graph Store Protocol). Write operations require an access token.

  ## Manifest Configuration

      @prefix gno:  <http://gno.app/> .
      @prefix gnoa: <http://gno.app/ns/adapter/> .

      <Qlever> a gnoa:Qlever
          ; gno:storeEndpointScheme "http"          # optional (default: "http")
          ; gno:storeEndpointHost "localhost"       # optional (default: "localhost")
          ; gno:storeEndpointPort 7001              # optional (default: 7001)
          ; gnoa:qleverAccessToken "my-access-token"  # required for write operations
      .

  ## Default Graph Semantics

  QLever uses union default graph semantics: the default graph is the union of all named
  graphs and the real default graph. The adapter automatically normalizes this by setting
  the `default-graph-uri` parameter to `<http://qlever.cs.uni-freiburg.de/builtin-functions/default-graph>`
  for query operations.

  ## Unsupported Operations

  QLever does not support the following SPARQL graph management operations:
  LOAD, CLEAR, CREATE, ADD, COPY, MOVE.
  Attempting these will return `{:error, %Gno.Store.UnsupportedOperationError{}}`.
  """

  use Grax.Schema

  import RDF.Sigils

  alias Gno.NS.GnoA
  alias Gno.Store.UnsupportedOperationError

  @unsupported_operations ~w[load clear create add copy move]a

  schema GnoA.Qlever < Gno.Store do
    # overrides the port default value
    property port: Gno.storeEndpointPort(), type: :integer, default: 7001
    property access_token: GnoA.qleverAccessToken(), type: :string

    # make these properties no longer required
    property query_endpoint: Gno.storeQueryEndpoint(), type: :iri, required: false
    property update_endpoint: Gno.storeUpdateEndpoint(), type: :iri, required: false
    property graph_store_endpoint: Gno.storeGraphStoreEndpoint(), type: :iri, required: false
  end

  # we need to define this after the Grax schema to be able to use %__MODULE__{} in the macro
  use Gno.Store.Adapter,
    name: :qlever,
    query_endpoint_path: "",
    update_endpoint_path: "",
    graph_store_endpoint_path: ""

  @impl true
  def default_graph_semantics, do: :union

  @impl true
  def default_graph_iri, do: ~I<http://qlever.cs.uni-freiburg.de/builtin-functions/default-graph>

  @impl true
  def handle_sparql(operation, adapter, graph_name, opts \\ [])

  def handle_sparql(%Operation{name: name}, %__MODULE__{} = adapter, _graph_name, _opts)
      when name in @unsupported_operations do
    {:error, UnsupportedOperationError.exception(operation: name, store: adapter)}
  end

  def handle_sparql(%Operation{} = operation, %__MODULE__{} = adapter, graph_name, opts) do
    opts = with_access_token_header(opts, adapter)
    GenSPARQL.handle(operation, adapter, graph_name, opts)
  end

  defp with_access_token_header(opts, %__MODULE__{access_token: nil}), do: opts

  defp with_access_token_header(opts, %__MODULE__{access_token: token}) do
    headers = Keyword.get(opts, :headers, %{})
    Keyword.put(opts, :headers, Map.put(headers, "Authorization", "Bearer #{token}"))
  end
end
