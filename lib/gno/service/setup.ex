defmodule Gno.Service.Setup do
  @moduledoc """
  Extensible setup command for initializing Gno repositories in the SPARQL store of a `Gno.Service`.
  """

  alias Gno.{Service, Store}
  alias Gno.Service.SetupError

  @options_schema [
    store_options: [
      type: :keyword_list,
      default: [],
      doc: "Options passed to the store adapter's setup functions"
    ],
    repository_data: [
      type_doc: "`t:RDF.Graph.input/0`",
      default: [],
      doc: "Additional RDF data to merge into the repository before storing"
    ],
    extension: [
      type: {:or, [:atom, nil]},
      default: nil,
      doc: "Extension module for application-specific setup logic"
    ],
    extension_opts: [
      type: :keyword_list,
      default: [],
      doc: "Options passed to the extension module callbacks"
    ],
    store_repository_metadata: [
      type: :boolean,
      default: true,
      doc: "If `false`, skips storing repository metadata in the triple store"
    ]
  ]

  @type options() :: [unquote(NimbleOptions.option_typespec(@options_schema))]

  @doc """
  Sets up a new repository for the given service.

  ## Options

  #{NimbleOptions.docs(@options_schema)}

  ## Examples

      # Simple setup with defaults
      {:ok, service} = Gno.Service.Setup.setup(service)

      # Setup without storing repository metadata
      {:ok, service} = Gno.Service.Setup.setup(service, store_repository_metadata: false)

      # Setup with extension
      {:ok, service} = Gno.Service.Setup.setup(service,
        extension: MyApp.Setup,
        extension_opts: [history: true, roles: [:admin, :user]]
      )

  """
  @spec setup(Service.t(), options()) :: {:ok, Service.t()} | {:error, term()}
  def setup(%_service_type{} = service, opts \\ []) do
    with {:ok, opts} <- NimbleOptions.validate(opts, @options_schema) do
      run_setup_pipeline(service, opts)
    end
  end

  defp run_setup_pipeline(service, opts) do
    store_opts = Keyword.get(opts, :store_options, [])

    with :ok <- Store.check_availability(service.store, store_opts),
         :ok <- prepare_store(service, store_opts),
         :ok <- ensure_not_already_setup(service, opts),
         {:ok, service} <- run_extension(service, opts),
         {:ok, service} <- initialize_repository(service, opts),
         {:ok, service} <- validate_setup(service, opts) do
      {:ok, service}
    else
      {:error, reason} ->
        {:error, SetupError.exception(reason: reason, service: service)}
    end
  end

  defp ensure_not_already_setup(service, opts) do
    case check(service, opts) do
      :ok -> {:error, :already_setup}
      {:error, :repository_not_found} -> :ok
      {:error, _} = error -> error
    end
  end

  defp prepare_store(service, opts) do
    case Store.setup(service.store, opts) do
      :ok -> :ok
      {:error, reason} -> {:error, {:store_preparation, reason}}
    end
  end

  defp initialize_repository(service, opts) do
    if Keyword.get(opts, :store_repository_metadata, true) do
      do_initialize_repository(service, opts)
    else
      {:ok, service}
    end
  end

  defp do_initialize_repository(service, opts) do
    service.repository
    |> Grax.to_rdf!()
    |> RDF.Graph.add(Keyword.get(opts, :repository_data, []))
    |> Gno.insert_data(service: service, graph: :repo)
    |> case do
      :ok -> {:ok, service}
      {:error, reason} -> {:error, {:repository_init, reason}}
    end
  end

  defp run_extension(service, opts) do
    case Keyword.get(opts, :extension) do
      nil -> {:ok, service}
      module when is_atom(module) -> module.setup(service, Keyword.get(opts, :extension_opts, []))
      invalid -> raise ArgumentError, "Invalid :extension value: #{inspect(invalid)}"
    end
  end

  defp validate_setup(service, opts) do
    if Keyword.get(opts, :store_repository_metadata, true) do
      case validate(service, opts) do
        :ok -> {:ok, service}
        {:error, reason} -> {:error, {:integrity_validation, reason}}
      end
    else
      {:ok, service}
    end
  end

  @doc """
  Checks if the repository is already set up.
  """
  @spec check(Service.t(), keyword()) :: :ok | {:error, term()}
  def check(%_service_type{} = service, opts \\ []) do
    store_opts = Keyword.get(opts, :store_options, [])

    with :ok <- Store.check_setup(service.store, store_opts) do
      case Keyword.get(opts, :extension) do
        nil ->
          Service.check_setup(service)

        extension when is_atom(extension) ->
          extension.check_setup(service, Keyword.get(opts, :extension_opts, []))

        invalid ->
          raise ArgumentError, "Invalid :extension value: #{inspect(invalid)}"
      end
    end
  end

  @doc """
  Validates the setup state including basic integrity and extension validations.
  """
  @spec validate(Service.t(), keyword()) :: :ok | {:error, term()}
  def validate(%_service_type{} = service, opts \\ []) do
    case Keyword.get(opts, :extension) do
      nil ->
        Service.validate_setup(service)

      extension when is_atom(extension) ->
        extension.validate(service, Keyword.get(opts, :extension_opts, []))

      invalid ->
        raise ArgumentError, "Invalid :extension value: #{inspect(invalid)}"
    end
  end

  @doc """
  Tears down the repository for the given service.

  > ### DESTRUCTIVE OPERATION {: .error}
  >
  > ⚠️  This will permanently delete repository data. ⚠️
  >
  > Only use in development/testing environments.

  ## Options

  #{NimbleOptions.docs(@options_schema)}

  ## Examples

      # Simple teardown with defaults
      :ok = Gno.Service.Setup.teardown(service)

      # Teardown with extension
      :ok = Gno.Service.Setup.teardown(service,
        extension: MyApp.Setup,
        extension_opts: [history: true, roles: [:admin, :user]]
      )

  """
  @spec teardown(Service.t(), options()) :: :ok | {:error, [term()]}
  def teardown(%_service_type{} = service, opts \\ []) do
    with {:ok, opts} <- NimbleOptions.validate(opts, @options_schema) do
      store_opts = Keyword.get(opts, :store_options, [])

      case Store.check_setup(service.store, store_opts) do
        :ok ->
          case do_teardown(service, opts) do
            [] -> :ok
            errors -> {:error, errors}
          end

        {:error, %Gno.Store.UnavailableError{reason: :dataset_not_found}} ->
          {:error, :not_setup}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp do_teardown(service, opts) do
    errors = []

    # Extension teardown
    errors =
      case Keyword.get(opts, :extension) do
        nil ->
          errors

        extension when is_atom(extension) ->
          case extension.teardown(service, Keyword.get(opts, :extension_opts, [])) do
            :ok -> errors
            {:error, error} -> [{:extension_teardown, error} | errors]
          end

        _ ->
          errors
      end

    # Service data removal
    errors =
      if Keyword.get(opts, :store_repository_metadata, true) do
        case Gno.drop(:service, service: service, silent: true) do
          :ok -> errors
          {:ok, _} -> errors
          {:error, error} -> [{:service_data, error} | errors]
        end
      else
        errors
      end

    # Store adapter teardown
    case Store.teardown(service.store, Keyword.get(opts, :store_options, [])) do
      :ok -> errors
      {:error, error} -> [{:store_adapter, error} | errors]
    end
  end
end
