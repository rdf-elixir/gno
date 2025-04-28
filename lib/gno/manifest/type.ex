defmodule Gno.Manifest.Type do
  @moduledoc """
  Behaviour for defining manifest types.
  """

  alias Gno.ManifestError
  alias RDF.Graph

  @type t :: module()
  @type schema :: Grax.Schema.t()

  @doc """
  Callback for returning the path to the default template for manifest generation.
  """
  @callback generator_template :: String.t()

  @doc """
  Callback for generating a manifest.
  """
  @callback generate(project_dir :: Path.t(), opts :: keyword()) :: :ok | {:error, any()}

  @doc """
  Callback for initializing a new graph with predefined setup.
  """
  @callback init_graph(opts :: keyword()) :: Graph.t()

  @doc """
  Callback for loading a graph from a file.
  """
  @callback load_file(file :: String.t(), opts :: keyword()) :: {:ok, Graph.t()} | {:error, any()}

  @doc """
  Callback for loading the manifest c from a graph.
  """
  @callback load_manifest(schema(), opts :: keyword()) :: {:ok, schema()} | {:error, any()}

  defmacro __using__(_) do
    quote do
      @behaviour unquote(__MODULE__)

      @impl true
      def generator_template do
        Gno.Manifest.Generator.default_template_dir()
      end

      @impl true
      def generate(project_dir, opts \\ []) do
        Gno.Manifest.Generator.generate(__MODULE__, project_dir, opts)
      end

      @impl true
      def init_graph(opts) do
        Gno.Manifest.Loader.init_graph(opts)
      end

      @impl true
      def load_file(file, opts) do
        Gno.Manifest.Loader.load_file(file, opts)
      end

      @impl true
      def load_manifest(manifest, opts) do
        Gno.Manifest.Loader.load_manifest(manifest, opts)
      end

      @spec manifest(keyword()) :: {:ok, t()} | {:error, ManifestError.t()}
      def manifest(opts \\ []) do
        Gno.Manifest.Loader.load(__MODULE__, opts)
      end

      def manifest!(opts \\ []), do: Gno.Utils.bang!(&manifest/1, [opts])

      def service(opts \\ []) do
        with {:ok, manifest} <- manifest(opts), do: {:ok, manifest.service}
      end

      def service!(opts \\ []), do: Gno.Utils.bang!(&service/1, [opts])

      def repository(opts \\ []) do
        with {:ok, service} <- service(opts), do: {:ok, service.repository}
      end

      def repository!(opts \\ []), do: Gno.Utils.bang!(&repository/1, [opts])

      def dataset(opts \\ []) do
        with {:ok, repository} <- repository(opts), do: {:ok, repository.dataset}
      end

      def dataset!(opts \\ []), do: Gno.Utils.bang!(&dataset/1, [opts])

      def store(opts \\ []) do
        with {:ok, service} <- service(opts), do: {:ok, service.store}
      end

      def store!(opts \\ []), do: Gno.Utils.bang!(&store/1, [opts])

      def service_type do
        case __MODULE__.__property__(:service) do
          %Grax.Schema.LinkProperty{type: {:resource, service_type}} -> service_type
          invalid -> raise "Invalid service type on #{__MODULE__}: #{inspect(invalid)}"
        end
      end

      defoverridable generate: 1,
                     generate: 2,
                     generator_template: 0,
                     init_graph: 1,
                     load_file: 2,
                     load_manifest: 2,
                     service: 0,
                     service: 1,
                     service!: 0,
                     service!: 1,
                     repository: 0,
                     repository: 1,
                     repository!: 0,
                     repository!: 1,
                     dataset: 0,
                     dataset: 1,
                     dataset!: 0,
                     dataset!: 1,
                     store: 0,
                     store: 1,
                     store!: 0,
                     store!: 1
    end
  end
end
