defmodule Gno.Store.Adapters.GraphDB do
  @moduledoc """
  A `Gno.Store.Adapter` implementation for [Ontotext GraphDB](https://graphdb.ontotext.com/).

  GraphDB is a RDF4J-based triplestore with reasoning support. It uses
  repository-based URL patterns following the RDF4J REST API convention.

  ## Manifest Configuration

      @prefix gno:  <https://w3id.org/gno#> .
      @prefix gnoa: <https://w3id.org/gno/store/adapter/> .

      <GraphDB> a gnoa:GraphDB
          ; gno:storeEndpointDataset "my-repository"    # required
          ; gno:storeEndpointScheme "http"              # optional (default: "http")
          ; gno:storeEndpointHost "localhost"           # optional (default: "localhost")
          ; gno:storeEndpointPort 7200                  # optional (default: 7200)
          ; gnoa:graphDbRdfStarSupport true             # optional (default: false)
      .

  ## Default Graph Semantics

  GraphDB uses union default graph semantics by default: the default graph
  is the union of all named graphs and the real default graph. The adapter
  automatically normalizes this by setting the `default-graph-uri` parameter
  to `<http://www.openrdf.org/schema/sesame#nil>` for query operations.

  This can be overridden per manifest with `gno:storeDefaultGraphSemantics "isolated"`.

  ## RDF-star Support

  GraphDB (RDF4J-based) encodes embedded RDF-star triples as `urn:rdf4j:triple:*`
  IRIs in standard SPARQL result formats. Setting `gnoa:graphDbRdfStarSupport` to
  `true` switches to RDF-star specific MIME types in Accept headers, so GraphDB
  returns native triple terms instead:

  - SELECT/ASK: `application/x-sparqlstar-results+json`
  - CONSTRUCT/DESCRIBE: `text/x-turtlestar`

  Requires GraphDB 10+.

  ## Prerequisites

  A GraphDB repository must be created before using this adapter (e.g. via
  the GraphDB Workbench UI or REST API). For test repositories, use `ruleset: "empty"`
  to avoid inference overhead.

  ## Administration

  This adapter provides access to GraphDB's [REST API](https://graphdb.ontotext.com/documentation/11.2/manage-repos-with-restapi.html)
  for health checks and repository information.
  """

  use Grax.Schema

  alias Gno.NS.GnoA

  schema GnoA.GraphDB < Gno.Store do
    # overrides the port default value
    property port: Gno.storeEndpointPort(), type: :integer, default: 7200
    property dataset: Gno.storeEndpointDataset(), type: :string, required: true

    # make these properties no longer required
    property query_endpoint: Gno.storeQueryEndpoint(), type: :iri, required: false
    property update_endpoint: Gno.storeUpdateEndpoint(), type: :iri, required: false
    property graph_store_endpoint: Gno.storeGraphStoreEndpoint(), type: :iri, required: false

    property rdf_star_support: GnoA.graphDbRdfStarSupport(), type: :boolean, default: false
  end

  # we need to define this after the Grax schema to be able to use %__MODULE__{} in the macro
  use Gno.Store.Adapter,
    name: :graph_db,
    query_endpoint_path: "",
    update_endpoint_path: "statements",
    graph_store_endpoint_path: "rdf-graphs/service",
    dataset_endpoint_segment_template: "repositories/{dataset}"

  import RDF.Sigils

  @select_star_accept "application/x-sparqlstar-results+json"
  @graph_star_accept "text/x-turtlestar"

  @impl true
  def default_graph_semantics, do: :union

  @impl true
  def default_graph_iri, do: ~I<http://www.openrdf.org/schema/sesame#nil>

  @impl true
  def handle_sparql(operation, adapter, graph_name, opts \\ [])

  def handle_sparql(
        %Operation{type: :query} = operation,
        %__MODULE__{rdf_star_support: true} = adapter,
        graph_name,
        opts
      ) do
    opts = with_rdf_star_accept(opts, operation)
    GenSPARQL.handle(operation, adapter, graph_name, opts)
  end

  def handle_sparql(%Operation{} = operation, %__MODULE__{} = adapter, graph_name, opts) do
    GenSPARQL.handle(operation, adapter, graph_name, opts)
  end

  defp with_rdf_star_accept(opts, %Operation{name: name}) when name in [:select, :ask] do
    opts
    |> Keyword.put(:accept_header, @select_star_accept)
    |> Keyword.put(:result_format, :json)
  end

  defp with_rdf_star_accept(opts, %Operation{name: name}) when name in [:construct, :describe] do
    opts
    |> Keyword.put(:accept_header, @graph_star_accept)
    |> Keyword.put(:result_format, :turtle)
  end

  @doc """
  Returns the GraphDB REST API base endpoint.
  """
  def rest_base(%__MODULE__{} = adapter) do
    %{adapter | dataset: nil}
    |> Gno.Store.endpoint_base!()
    |> Path.join("rest")
  end

  @doc """
  Returns the repositories endpoint for repository management operations.
  """
  def repositories_endpoint(%__MODULE__{} = adapter) do
    Path.join(rest_base(adapter), "repositories")
  end

  @doc """
  Returns the repository-specific endpoint for the adapter's repository.
  """
  def repository_endpoint(%__MODULE__{} = adapter) do
    repository_endpoint(adapter, adapter.dataset)
  end

  @doc """
  Returns the repository-specific endpoint for a given repository name.
  """
  def repository_endpoint(%__MODULE__{} = adapter, repository_name) do
    Path.join(repositories_endpoint(adapter), repository_name)
  end

  @doc """
  Returns the repository size endpoint.
  """
  def repository_size_endpoint(%__MODULE__{} = adapter) do
    repository_size_endpoint(adapter, adapter.dataset)
  end

  @doc """
  Returns the repository size endpoint for a given repository name.
  """
  def repository_size_endpoint(%__MODULE__{} = adapter, repository_name) do
    Path.join(repository_endpoint(adapter, repository_name), "size")
  end

  @doc """
  Checks if the GraphDB server is available by listing repositories.
  """
  def ping(%__MODULE__{} = adapter, _opts \\ []) do
    ping_url = repositories_endpoint(adapter)

    case Tesla.get(ping_url) do
      {:ok, %Tesla.Env{status: 200}} ->
        :ok

      {:ok, %Tesla.Env{status: status}} ->
        {:error,
         Gno.Store.UnavailableError.exception(
           reason: :server_unreachable,
           store: adapter,
           endpoint: ping_url,
           error: "HTTP #{status}"
         )}

      {:error, reason} ->
        {:error,
         Gno.Store.UnavailableError.exception(
           reason: :server_unreachable,
           store: adapter,
           endpoint: ping_url,
           error: reason
         )}
    end
  end

  def ping?(%__MODULE__{} = adapter, opts \\ []), do: ping(adapter, opts) == :ok

  @doc """
  Fetches information about all repositories.
  """
  def all_repositories_info(%__MODULE__{} = adapter) do
    admin_request(adapter, repositories_endpoint(adapter))
  end

  @doc """
  Fetches information about the adapter's repository.
  """
  def repository_info(%__MODULE__{} = adapter) do
    repository_info(adapter, adapter.dataset)
  end

  @doc """
  Fetches information about a specific repository.
  """
  def repository_info(%__MODULE__{} = adapter, repository_name) do
    endpoint_url = repository_endpoint(adapter, repository_name)

    case Tesla.get(endpoint_url, headers: [{"accept", "application/json"}]) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} -> {:ok, data}
          {:error, error} -> {:error, decode_error(adapter, endpoint_url, error)}
        end

      {:ok, %Tesla.Env{status: 404}} ->
        {:ok, nil}

      {:ok, %Tesla.Env{status: status}} ->
        {:error, admin_error(adapter, endpoint_url, "HTTP #{status}")}

      {:error, reason} ->
        {:error, admin_error(adapter, endpoint_url, reason)}
    end
  end

  @doc """
  Fetches the size (number of statements) of the adapter's repository.
  """
  def repository_size(%__MODULE__{} = adapter) do
    repository_size(adapter, adapter.dataset)
  end

  @doc """
  Fetches the size (number of statements) of a specific repository.
  """
  def repository_size(%__MODULE__{} = adapter, repository_name) do
    endpoint_url = repository_size_endpoint(adapter, repository_name)

    case Tesla.get(endpoint_url, headers: [{"accept", "application/json"}]) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"total" => total}} when is_integer(total) ->
            {:ok, total}

          {:ok, _} ->
            {:error, admin_error(adapter, endpoint_url, "Unexpected size response: #{body}")}

          {:error, error} ->
            {:error, decode_error(adapter, endpoint_url, error)}
        end

      {:ok, %Tesla.Env{status: status}} ->
        {:error, admin_error(adapter, endpoint_url, "HTTP #{status}")}

      {:error, reason} ->
        {:error, admin_error(adapter, endpoint_url, reason)}
    end
  end

  @impl true
  def check_availability(%__MODULE__{} = adapter, opts \\ []), do: ping(adapter, opts)

  @impl true
  def check_setup(%__MODULE__{} = adapter, opts) do
    with :ok <-
           (if Keyword.get(opts, :check_availability, true) do
              check_availability(adapter, opts)
            else
              :ok
            end) do
      case repository_info(adapter) do
        {:ok, nil} ->
          {:error,
           Gno.Store.UnavailableError.exception(
             reason: :dataset_not_found,
             store: adapter,
             endpoint: repositories_endpoint(adapter)
           )}

        {:ok, _} ->
          :ok

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp admin_request(%__MODULE__{} = adapter, endpoint_url) do
    with {:ok, %Tesla.Env{status: 200, body: body}} <- Tesla.get(endpoint_url),
         {:ok, data} <- Jason.decode(body) do
      {:ok, data}
    else
      {:ok, %Tesla.Env{status: status}} ->
        {:error, admin_error(adapter, endpoint_url, "Admin request failed: HTTP #{status}")}

      {:error, %Jason.DecodeError{} = decode_error} ->
        {:error, decode_error(adapter, endpoint_url, decode_error)}

      {:error, reason} ->
        {:error, admin_error(adapter, endpoint_url, reason)}
    end
  end

  defp admin_error(adapter, endpoint_url, error) do
    %Gno.Store.UnavailableError{
      reason: :admin_query_failed,
      store: adapter,
      endpoint: endpoint_url,
      error: error
    }
  end

  defp decode_error(adapter, endpoint_url, error) do
    admin_error(adapter, endpoint_url, "Failed to decode response: #{inspect(error)}")
  end
end
