defmodule Gno.Store do
  @moduledoc """
  Base Grax schema for triple stores hosting a `DCATR.Repository`.

  Concrete store types are defined by `Gno.Store.Adapter` implementations
  (e.g. `Gno.Store.Adapters.Fuseki`). This module provides generic endpoint
  resolution and delegates SPARQL operations to the appropriate adapter.

  It can also be used directly as a generic adapter for any SPARQL 1.1
  protocol-compliant triple store that has no dedicated adapter implementation:

      @prefix gno: <http://gno.app/> .

      <MyStore> a gno:Store
          ; gno:storeQueryEndpoint <http://localhost:7878/query>       # required
          ; gno:storeUpdateEndpoint <http://localhost:7878/update>     # optional
          ; gno:storeGraphStoreEndpoint <http://localhost:7878/store>  # optional
      .
  """

  use Grax.Schema

  @behaviour Gno.Store.Adapter

  alias Gno.Store.{GenSPARQL, InvalidEndpointError}
  alias RDF.NS.RDFS

  import Gno.Utils, only: [bang!: 2]

  @adapter_classes "priv/vocabs/gno_store_adapter.ttl"
                   |> RDF.Turtle.read_file!()
                   |> RDF.Graph.query({:adapter?, RDFS.subClassOf(), Gno.Store})
                   |> Enum.map(fn %{adapter: adapter_class} -> adapter_class end)
  @doc """
  Returns the list of known store adapter class IRIs.
  """
  def adapter_classes, do: @adapter_classes

  @doc """
  Returns the list of available store adapter modules.
  """
  def adapters, do: @adapter_classes |> Enum.map(&Grax.schema/1) |> Enum.reject(&is_nil/1)

  schema Gno.Store do
    property query_endpoint: Gno.storeQueryEndpoint(), type: :iri, required: true
    property update_endpoint: Gno.storeUpdateEndpoint(), type: :iri
    property graph_store_endpoint: Gno.storeGraphStoreEndpoint(), type: :iri

    property scheme: Gno.storeEndpointScheme(), type: :string, default: "http"
    property host: Gno.storeEndpointHost(), type: :string, default: "localhost"
    property port: Gno.storeEndpointPort(), type: :integer, default: 7878
    property userinfo: Gno.storeEndpointUserInfo(), type: :string
  end

  @doc """
  Returns the base endpoint URL for the store.

  Constructed from the store's scheme, host, port, and dataset properties.
  Returns `{:error, ...}` if the required properties are missing.
  """
  def endpoint_base(%__MODULE__{} = store) do
    {:error,
     InvalidEndpointError.exception("endpoint_base not supported on generic #{inspect(store)}")}
  end

  def endpoint_base(%_adapter_type{host: nil} = store) do
    {:error, InvalidEndpointError.exception("missing endpoint_base info on #{inspect(store)}")}
  end

  def endpoint_base(%_adapter_type{scheme: nil} = store) do
    {:error, InvalidEndpointError.exception("missing endpoint_base info on #{inspect(store)}")}
  end

  def endpoint_base(%adapter_type{dataset: dataset} = store) when not is_nil(dataset) do
    with {:ok, segment} <- adapter_type.dataset_endpoint_segment(store),
         {:ok, endpoint_base} <- endpoint_base(%{store | dataset: nil}) do
      {:ok, Path.join(endpoint_base, segment)}
    end
  end

  def endpoint_base(%_adapter_type{scheme: scheme, host: host, port: port, userinfo: userinfo}) do
    {:ok, to_string(%URI{scheme: scheme, host: host, port: port, userinfo: userinfo})}
  end

  def endpoint_base!(store), do: bang!(&endpoint_base/1, [store])

  @doc """
  Returns the base endpoint URL with the given path appended.
  """
  def endpoint_base_with_path(%_adapter_type{} = store, path) do
    with {:ok, endpoint_base} <- endpoint_base(store) do
      {:ok, Path.join(endpoint_base, path)}
    end
  end

  def endpoint_base_with_path!(store, path), do: bang!(&endpoint_base_with_path/2, [store, path])

  @doc """
  Returns the SPARQL query endpoint URL for the store.

  Uses the explicitly configured `query_endpoint` if set, otherwise
  delegates to the adapter's `c:Gno.Store.Adapter.determine_query_endpoint/1`.
  """
  def query_endpoint(%adapter_type{query_endpoint: nil} = store_adapter),
    do: adapter_type.determine_query_endpoint(store_adapter)

  def query_endpoint(%_adapter_type{query_endpoint: query_endpoint}),
    do: {:ok, to_string(query_endpoint)}

  def query_endpoint!(store), do: bang!(&query_endpoint/1, [store])

  @doc """
  Returns the SPARQL update endpoint URL for the store.
  """
  def update_endpoint(%adapter_type{update_endpoint: nil} = store_adapter),
    do: adapter_type.determine_update_endpoint(store_adapter)

  def update_endpoint(%_adapter_type{update_endpoint: update_endpoint}),
    do: {:ok, to_string(update_endpoint)}

  def update_endpoint!(store), do: bang!(&update_endpoint/1, [store])

  @doc """
  Returns the SPARQL Graph Store Protocol endpoint URL for the store.
  """
  def graph_store_endpoint(%adapter_type{graph_store_endpoint: nil} = store_adapter),
    do: adapter_type.determine_graph_store_endpoint(store_adapter)

  def graph_store_endpoint(%_adapter_type{graph_store_endpoint: graph_store_endpoint}),
    do: {:ok, to_string(graph_store_endpoint)}

  def graph_store_endpoint!(store), do: bang!(&graph_store_endpoint/1, [store])

  @impl true
  def determine_query_endpoint(%__MODULE__{} = store) do
    {:error,
     InvalidEndpointError.exception("undefined query_endpoint on generic #{inspect(store)}")}
  end

  @impl true
  def determine_update_endpoint(%__MODULE__{} = store) do
    {:error,
     InvalidEndpointError.exception("undefined update_endpoint on generic #{inspect(store)}")}
  end

  @impl true
  def determine_graph_store_endpoint(%__MODULE__{} = store) do
    {:error,
     InvalidEndpointError.exception("undefined graph_store_endpoint on generic #{inspect(store)}")}
  end

  @impl true
  def dataset_endpoint_segment(%__MODULE__{} = store) do
    {:error,
     InvalidEndpointError.exception(
       "dataset_endpoint_segment not supported on generic #{inspect(store)}"
     )}
  end

  def dataset_endpoint_segment(%adapter_type{} = store_adapter),
    do: adapter_type.dataset_endpoint_segment(store_adapter)

  @impl true
  def handle_sparql(operation, store, graph_name, opts \\ [])

  def handle_sparql(operation, %__MODULE__{} = store, graph_name, opts) do
    GenSPARQL.handle(operation, store, graph_name, opts)
  end

  def handle_sparql(operation, %store_adapter{} = store, graph_name, opts) do
    store_adapter.handle_sparql(operation, store, graph_name, opts)
  end

  @impl true
  def setup(store, opts \\ [])
  def setup(%__MODULE__{}, _opts), do: :ok
  def setup(%store_adapter{} = store, opts), do: store_adapter.setup(store, opts)

  @impl true
  def teardown(store, opts \\ [])
  def teardown(%__MODULE__{}, _opts), do: :ok
  def teardown(%store_adapter{} = store, opts), do: store_adapter.teardown(store, opts)

  @impl true
  def check_availability(store, opts \\ [])
  def check_availability(%__MODULE__{} = store, opts), do: do_check_availability(store, opts)

  def check_availability(%store_adapter{} = store, opts),
    do: store_adapter.check_availability(store, opts)

  @impl true
  def check_setup(store, opts \\ [])

  def check_setup(%__MODULE__{} = store, opts) do
    if Keyword.get(opts, :check_availability, true) do
      do_check_availability(store, opts)
    else
      :ok
    end
  end

  def check_setup(%store_adapter{} = store, opts), do: store_adapter.check_setup(store, opts)

  @doc false
  def do_check_availability(store, opts) do
    "ASK { ?s ?p ?o }"
    |> Gno.Store.SPARQL.Operation.ask!()
    |> handle_sparql(store, nil, opts)
    |> case do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        {:error,
         Gno.Store.UnavailableError.exception(
           reason: :query_failed,
           store: store,
           endpoint:
             case query_endpoint(store) do
               {:ok, url} -> url
               _ -> nil
             end,
           error: reason
         )}
    end
  end
end
