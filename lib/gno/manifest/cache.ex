defmodule Gno.Manifest.Cache do
  @moduledoc """
  Provides caching functionality for Gno manifests.

  The cache stores manifests to avoid unnecessary reloading.
  """

  use GenServer

  alias Gno.{Manifest, ManifestError}
  alias Gno.Manifest.{LoadPath, Loader}

  @table_name :gno_manifest_cache

  @doc """
  Starts the cache GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    table = :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{table: table}}
  end

  @doc """
  Gets a manifest from the cache or loads it if not present or if reload is requested.

  ## Options

  - `:reload` - When `true`, forces reloading the manifest and updates the cache
  - Any other options are passed to the manifest loader
  """
  @spec manifest(Manifest.Type.t(), keyword()) ::
          {:ok, Manifest.Type.schema()} | {:error, ManifestError.t()}
  def manifest(manifest_type, opts \\ []) do
    {reload?, opts} = Keyword.pop(opts, :reload, false)
    key = {manifest_type, LoadPath.load_path(opts)}

    if reload? do
      load_and_cache(manifest_type, key, opts)
    else
      case :ets.lookup(@table_name, key) do
        [{^key, manifest}] -> {:ok, manifest}
        [] -> load_and_cache(manifest_type, key, opts)
      end
    end
  end

  defp load_and_cache(manifest_type, key, opts) do
    with {:ok, manifest} = result <- Loader.load(manifest_type, opts) do
      :ets.insert(@table_name, {key, manifest})
      result
    end
  end

  @doc """
  Removes a specific manifest from the cache.
  """
  @spec invalidate(Manifest.Type.t(), keyword()) :: :ok
  def invalidate(manifest_type, opts \\ []) do
    :ets.delete(@table_name, {manifest_type, LoadPath.load_path(opts)})

    :ok
  end

  @doc """
  Clears the entire cache.

  Useful for testing purposes.
  """
  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@table_name)
    :ok
  end
end
