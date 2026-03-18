defmodule Gno.Store.Adapters.Fuseki do
  @moduledoc """
  A `Gno.Store.Adapter` implementation for [Apache Jena Fuseki](https://jena.apache.org/documentation/fuseki2/).

  ## Manifest Configuration

      @prefix gno:  <http://gno.app/> .
      @prefix gnoa: <http://gno.app/ns/adapter/> .

      <Fuseki> a gnoa:Fuseki
          ; gno:storeEndpointScheme "http"         # optional (default: "http")
          ; gno:storeEndpointHost "localhost"      # optional (default: "localhost")
          ; gno:storeEndpointPort 3030             # optional (default: 3030)
          ; gno:storeEndpointDataset "my-dataset"  # required
      .

  ## Administration

  This adapter also provides access to Fuseki's
  [HTTP Administration Protocol](https://jena.apache.org/documentation/fuseki2/fuseki-server-protocol.html)
  for dataset management, server health checks, statistics, and backups.
  """

  use Grax.Schema

  alias Gno.NS.GnoA

  schema GnoA.Fuseki < Gno.Store do
    # overrides the port default value
    property port: Gno.storeEndpointPort(), type: :integer, default: 3030
    property dataset: Gno.storeEndpointDataset(), type: :string, required: true

    # make these properties no longer required
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

  require Logger
  import RDF.Sigils

  @default_db_type (case DCATR.Manifest.env() do
                      :test -> "mem"
                      _ -> "tdb"
                    end)

  @impl true
  def default_graph_semantics, do: :isolated

  @impl true
  def default_graph_iri, do: ~I<urn:x-arq:DefaultGraph>

  @doc """
  Returns the Fuseki HTTP Administration API base endpoint.
  """
  def admin_base(%__MODULE__{} = adapter) do
    %{adapter | dataset: nil}
    |> Gno.Store.endpoint_base!()
    |> Path.join("$")
  end

  @doc """
  Returns the ping endpoint for server health checks.
  """
  def ping_endpoint(%__MODULE__{} = adapter) do
    Path.join(admin_base(adapter), "ping")
  end

  @doc """
  Returns the server information endpoint.
  """
  def server_endpoint(%__MODULE__{} = adapter) do
    Path.join(admin_base(adapter), "server")
  end

  @doc """
  Returns the datasets endpoint for dataset management operations.
  """
  def datasets_admin_endpoint(%__MODULE__{} = adapter) do
    Path.join(admin_base(adapter), "datasets")
  end

  @doc """
  Returns the dataset-specific admin endpoint for the adapter's dataset.
  """
  def dataset_admin_endpoint(%__MODULE__{} = adapter) do
    dataset_admin_endpoint(adapter, adapter.dataset)
  end

  @doc """
  Returns the dataset-specific admin endpoint for a given dataset name.
  """
  def dataset_admin_endpoint(%__MODULE__{} = adapter, dataset_name) do
    Path.join(datasets_admin_endpoint(adapter), dataset_name)
  end

  @doc """
  Returns the statistics endpoint for all datasets.
  """
  def stats_endpoint(%__MODULE__{} = adapter) do
    Path.join(admin_base(adapter), "stats")
  end

  @doc """
  Returns the statistics endpoint for the adapter's dataset.
  """
  def dataset_stats_endpoint(%__MODULE__{} = adapter) do
    dataset_stats_endpoint(adapter, adapter.dataset)
  end

  @doc """
  Returns the statistics endpoint for a specific dataset.
  """
  def dataset_stats_endpoint(%__MODULE__{} = adapter, dataset_name) do
    Path.join(stats_endpoint(adapter), dataset_name)
  end

  @doc """
  Returns the metrics endpoint.
  """
  def metrics_endpoint(%__MODULE__{} = adapter) do
    Path.join(admin_base(adapter), "metrics")
  end

  @doc """
  Returns the backup endpoint for the adapter's dataset.
  """
  def backup_endpoint(%__MODULE__{} = adapter) do
    backup_endpoint(adapter, adapter.dataset)
  end

  @doc """
  Returns the backup endpoint for a specific dataset.
  """
  def backup_endpoint(%__MODULE__{} = adapter, dataset_name) do
    Path.join(admin_base(adapter), "backup/#{dataset_name}")
  end

  @doc """
  Returns the backups list endpoint.
  """
  def backups_list_endpoint(%__MODULE__{} = adapter) do
    Path.join(admin_base(adapter), "backups-list")
  end

  @doc """
  Returns the tasks endpoint for monitoring background operations.
  """
  def tasks_endpoint(%__MODULE__{} = adapter) do
    Path.join(admin_base(adapter), "tasks")
  end

  @doc """
  Returns the task-specific endpoint for a given task ID.
  """
  def task_endpoint(%__MODULE__{} = adapter, task_id) do
    Path.join(tasks_endpoint(adapter), to_string(task_id))
  end

  @doc """
  Returns the compact endpoint for the adapter's dataset.
  """
  def compact_endpoint(%__MODULE__{} = adapter) do
    compact_endpoint(adapter, adapter.dataset)
  end

  @doc """
  Returns the compact endpoint for a specific dataset.
  """
  def compact_endpoint(%__MODULE__{} = adapter, dataset_name) do
    Path.join(admin_base(adapter), "compact/#{dataset_name}")
  end

  @doc """
  Returns the sleep endpoint.
  """
  def sleep_endpoint(%__MODULE__{} = adapter) do
    Path.join(admin_base(adapter), "sleep")
  end

  @doc """
  Checks if the Fuseki server is available by pinging it.
  """
  def ping(%__MODULE__{} = adapter, _opts \\ []) do
    ping_url = ping_endpoint(adapter)

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
  Fetches server information from the Fuseki admin endpoint.
  """
  def server_info(%__MODULE__{} = adapter) do
    admin_request(adapter, server_endpoint(adapter))
  end

  @doc """
  Fetches all datasets from the Fuseki admin endpoint.
  """
  def all_datasets_info(%__MODULE__{} = adapter) do
    with {:ok, %{"datasets" => datasets}} <-
           admin_request(adapter, datasets_admin_endpoint(adapter)) do
      {:ok, datasets}
    else
      {:ok, _} ->
        {:error,
         "Failed to parse datasets from Fuseki admin endpoint: no \"datasets\" object found"}

      error ->
        error
    end
  end

  @doc """
  Fetches information for the adapter's dataset.
  """
  def dataset_info(%__MODULE__{} = adapter) do
    dataset_info(adapter, adapter.dataset)
  end

  @doc """
  Fetches information for a specific dataset.
  """
  def dataset_info(%__MODULE__{} = adapter, dataset_name) do
    with {:ok, datasets} <- all_datasets_info(adapter) do
      {:ok, Enum.find(datasets, fn ds -> ds["ds.name"] == "/#{dataset_name}" end)}
    end
  end

  @doc """
  Fetches statistics for all datasets.
  """
  def all_stats(%__MODULE__{} = adapter) do
    admin_request(adapter, stats_endpoint(adapter))
  end

  @doc """
  Fetches statistics for the adapter's dataset.
  """
  def dataset_stats(%__MODULE__{} = adapter) do
    dataset_stats(adapter, adapter.dataset)
  end

  @doc """
  Fetches statistics for a specific dataset.
  """
  def dataset_stats(%__MODULE__{} = adapter, dataset_name) do
    admin_request(adapter, dataset_stats_endpoint(adapter, dataset_name))
  end

  @doc """
  Fetches information about running tasks.
  """
  def tasks_info(%__MODULE__{} = adapter) do
    admin_request(adapter, tasks_endpoint(adapter))
  end

  @doc """
  Fetches information about a specific task.
  """
  def task_info(%__MODULE__{} = adapter, task_id) do
    admin_request(adapter, task_endpoint(adapter, task_id))
  end

  @doc """
  Fetches server metrics.
  """
  def metrics(%__MODULE__{} = adapter) do
    # Metrics endpoint returns plain text, not JSON
    metrics_url = metrics_endpoint(adapter)

    case Tesla.get(metrics_url) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Tesla.Env{status: status}} ->
        {:error,
         %Gno.Store.UnavailableError{
           reason: :admin_query_failed,
           store: adapter,
           endpoint: metrics_url,
           error: "Metrics request failed: HTTP #{status}"
         }}

      {:error, reason} ->
        {:error,
         %Gno.Store.UnavailableError{
           reason: :admin_query_failed,
           store: adapter,
           endpoint: metrics_url,
           error: reason
         }}
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
      case dataset_info(adapter) do
        {:ok, nil} ->
          {:error,
           Gno.Store.UnavailableError.exception(
             reason: :dataset_not_found,
             store: adapter,
             endpoint: datasets_admin_endpoint(adapter)
           )}

        {:ok, _} ->
          :ok

        {:error, error} ->
          {:error, error}
      end
    end
  end

  @impl true
  def setup(%__MODULE__{dataset: dataset} = adapter, opts \\ []) do
    create_dataset(adapter, dataset, opts)
  end

  @impl true
  def teardown(%__MODULE__{dataset: dataset} = adapter, _opts \\ []) do
    delete_dataset(adapter, dataset)
  end

  defp create_dataset(%__MODULE__{} = adapter, dataset_name, opts) do
    admin_url = datasets_admin_endpoint(adapter)
    db_type = Keyword.get(opts, :db_type, @default_db_type)
    client = Tesla.client([Tesla.Middleware.FormUrlencoded])

    case Tesla.post(client, admin_url, %{dbType: db_type, dbName: dataset_name}) do
      {:ok, %Tesla.Env{status: status}} when status in [200, 201] ->
        :ok

      {:ok, %Tesla.Env{status: 409}} ->
        case Keyword.get(opts, :on_existing_dataset, :ignore) do
          :ignore -> :ok
          :warn -> Logger.warning("Dataset '#{dataset_name}' already exists on Fuseki server")
          :error -> {:error, "Dataset '#{dataset_name}' already exists on Fuseki server"}
          :raise -> raise "Dataset '#{dataset_name}' already exists on Fuseki server"
          invalid -> raise "Invalid :on_existing_dataset value: #{inspect(invalid)}"
        end

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, "Failed to create dataset '#{dataset_name}': HTTP #{status} - #{body}"}

      {:error, reason} ->
        {:error, "Failed to create dataset '#{dataset_name}': #{inspect(reason)}"}
    end
  end

  defp delete_dataset(%__MODULE__{} = adapter, dataset_name) do
    dataset_url = dataset_admin_endpoint(adapter, dataset_name)

    case Tesla.delete(dataset_url) do
      {:ok, %Tesla.Env{status: 200}} ->
        :ok

      {:ok, %Tesla.Env{status: 404}} ->
        :ok

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, "Failed to delete dataset '#{dataset_name}': HTTP #{status} - #{body}"}

      {:error, reason} ->
        {:error, "Failed to delete dataset '#{dataset_name}': #{inspect(reason)}"}
    end
  end

  @doc false
  defp admin_request(%__MODULE__{} = adapter, endpoint_url) do
    with {:ok, %Tesla.Env{status: 200, body: body}} <- Tesla.get(endpoint_url),
         {:ok, data} <- Jason.decode(body) do
      {:ok, data}
    else
      {:ok, %Tesla.Env{status: status}} ->
        {:error,
         %Gno.Store.UnavailableError{
           reason: :admin_query_failed,
           store: adapter,
           endpoint: endpoint_url,
           error: "Admin request failed: HTTP #{status}"
         }}

      {:error, %Jason.DecodeError{} = decode_error} ->
        {:error,
         %Gno.Store.UnavailableError{
           reason: :admin_query_failed,
           store: adapter,
           endpoint: endpoint_url,
           error: "Failed to decode response: #{inspect(decode_error)}"
         }}

      {:error, reason} ->
        {:error,
         %Gno.Store.UnavailableError{
           reason: :admin_query_failed,
           store: adapter,
           endpoint: endpoint_url,
           error: reason
         }}
    end
  end
end
