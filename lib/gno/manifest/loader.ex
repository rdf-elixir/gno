defmodule Gno.Manifest.Loader do
  @moduledoc """
  Loads the manifest from the configured load path.
  """

  alias Gno.Manifest.{LoadPath, LoadingError}
  alias Gno.ManifestError
  alias RDF.Graph

  @doc """
  Returns the configured base IRI for the manifest graph.
  """
  def base(opts \\ []) do
    Keyword.get(opts, :base, Application.get_env(:gno, :manifest_base))
  end

  @doc """
  Loads the manifest from the configured load path.
  """
  def load(manifest_type, opts \\ []) do
    load_path = LoadPath.load_path(opts)
    opts = Keyword.put_new(opts, :load_path, load_path)

    with {:ok, graph} <- load_graph(manifest_type, opts) do
      manifest =
        graph
        |> manifest_id(opts)
        |> manifest_type.build!(load_path: load_path, graph: graph)

      case manifest_type.load_manifest(manifest, opts) do
        {:ok, _manifest} = ok -> ok
        {:error, %ManifestError{}} = error -> error
        {:error, error} -> {:error, ManifestError.exception(manifest: manifest, reason: error)}
      end
    end
  end

  defp manifest_id(graph, opts) do
    Keyword.get(opts, :manifest_id) ||
      Application.get_env(:gno, :manifest_id) ||
      graph.base_iri ||
      RDF.bnode()
  end

  def service_type(manifest_type) do
    case manifest_type.__property__(:service) do
      {:resource, service_type} -> service_type
      invalid -> raise "Invalid service type on manifest #{manifest_type}: #{inspect(invalid)}"
    end
  end

  @doc """
  Loads the manifest graph from the configured load path.
  """
  @spec load_graph(module(), opts :: keyword()) ::
          {:ok, Graph.t()} | {:error, LoadingError.t()}
  def load_graph(manifest_type, opts \\ []) do
    opts
    |> LoadPath.files()
    |> do_load_graph(manifest_type, opts)
  end

  defp do_load_graph([], _manifest_type, _opts) do
    {:error, LoadingError.exception(reason: :missing)}
  end

  defp do_load_graph(files, manifest_type, opts) do
    Enum.reduce_while(files, manifest_type.init_graph(opts), fn
      path, {:ok, acc} ->
        case manifest_type.load_file(path, opts) do
          {:ok, nil} ->
            {:cont, {:ok, acc}}

          {:ok, graph} ->
            {:cont, {:ok, Graph.put_properties(acc, graph)}}

          {:error, error} ->
            {:halt, {:error, LoadingError.exception(file: path, reason: error)}}
        end

      _, {:error, error} ->
        {:halt, {:error, LoadingError.exception(file: :init_graph, reason: error)}}
    end)
  end

  ###########################################################################
  # Default implementation of the `Gno.Manifest.Adapter` callbacks.
  ###########################################################################

  def init_graph(opts \\ []), do: {:ok, Graph.new(base: base(opts))}

  def load_file(file, opts \\ []) do
    RDF.read_file(file, base: base(opts))
  end

  def load_manifest(
        %manifest_type{__id__: _, graph: graph, load_path: _, service: _} = manifest,
        opts \\ []
      ) do
    service_type = manifest_type.service_type()

    with {:ok, service_id} <- service_id(service_type, graph, opts),
         {:ok, service} <- service_type.load(graph, service_id, depth: 99) do
      Grax.put(manifest, :service, service)
    end
  end

  defp service_id(service_type, graph, opts) do
    if service_id = Keyword.get(opts, :service_id) do
      {:ok, service_id}
    else
      find_service_id(service_type, graph)
    end
  end

  defp find_service_id(service_type, graph) do
    case Graph.query(graph, {:service?, RDF.type(), RDF.iri(service_type.__class__())}) do
      [%{service: service}] -> {:ok, service}
      [] -> {:error, ManifestError.exception(manifest: graph, reason: :no_service)}
      multi -> {:error, ManifestError.exception(manifest: multi, reason: :multiple_services)}
    end
  end
end
