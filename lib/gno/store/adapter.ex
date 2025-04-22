defmodule Gno.Store.Adapter do
  @moduledoc """
  A behaviour for SPARQL triple stores hosting a `Gno.Repository`.
  """

  alias Gno.Store.SPARQL.Operation
  alias Gno.Store.InvalidEndpointError

  @type type :: module
  @type t :: struct

  @type endpoint_url :: String.t() | nil
  @type graph_name :: RDF.IRI.t() | nil
  @type result :: SPARQL.Query.Result.t() | RDF.Data.t() | nil

  @callback determine_query_endpoint(t()) :: {:ok, endpoint_url()} | {:error, any}
  @callback determine_update_endpoint(t()) :: {:ok, endpoint_url()} | {:error, any}
  @callback determine_graph_store_endpoint(t()) :: {:ok, endpoint_url()} | {:error, any}

  @callback dataset_endpoint_segment(t()) :: {:ok, binary()} | {:error, any}

  @callback handle_sparql(Operation.t(), t(), graph_name(), keyword) ::
              {:ok, result()} | :ok | {:error, any}

  defmacro __using__(adapter_spec) do
    {dataset_endpoint_segment_template, adapter_spec} =
      Keyword.pop(adapter_spec, :dataset_endpoint_segment_template)

    {query_endpoint_path, adapter_spec} = Keyword.pop(adapter_spec, :query_endpoint_path)
    {update_endpoint_path, adapter_spec} = Keyword.pop(adapter_spec, :update_endpoint_path)

    {graph_store_endpoint_path, _adapter_spec} =
      Keyword.pop(adapter_spec, :graph_store_endpoint_path)

    quote do
      @behaviour Gno.Store.Adapter

      alias Gno.NS.GnoA

      alias Gno.Store.GenSPARQL
      alias Gno.Store.SPARQL.Operation

      if unquote(query_endpoint_path) do
        @impl true
        def determine_query_endpoint(%__MODULE__{} = adapter) do
          Gno.Store.endpoint_base_with_path(adapter, unquote(query_endpoint_path))
        end

        defoverridable determine_query_endpoint: 1
      end

      if unquote(update_endpoint_path) do
        @impl true
        def determine_update_endpoint(%__MODULE__{} = adapter) do
          Gno.Store.endpoint_base_with_path(adapter, unquote(update_endpoint_path))
        end

        defoverridable determine_update_endpoint: 1
      end

      if unquote(graph_store_endpoint_path) do
        @impl true
        def determine_graph_store_endpoint(%__MODULE__{} = adapter) do
          Gno.Store.endpoint_base_with_path(adapter, unquote(graph_store_endpoint_path))
        end

        defoverridable determine_graph_store_endpoint: 1
      end

      @impl true
      if unquote(dataset_endpoint_segment_template) do
        @dataset_endpoint_segment_template unquote(dataset_endpoint_segment_template)
                                           |> YuriTemplate.parse()
                                           |> (case do
                                                 {:ok, template} -> template
                                                 {:error, error} -> raise error
                                               end)
        @dataset_endpoint_segment_template_parameters YuriTemplate.parameters(
                                                        @dataset_endpoint_segment_template
                                                      )

        def dataset_endpoint_segment(%__MODULE__{} = adapter) do
          adapter_vars =
            adapter
            |> Map.from_struct()
            |> Keyword.new()

          @dataset_endpoint_segment_template_parameters
          |> Enum.reject(fn param -> adapter_vars[param] end)
          |> case do
            [] ->
              YuriTemplate.expand(@dataset_endpoint_segment_template, adapter_vars)

            missing ->
              {:error,
               InvalidEndpointError.exception(
                 "missing dataset template params #{inspect(missing)} on store #{inspect(adapter)}"
               )}
          end
        end
      else
        def dataset_endpoint_segment(%__MODULE__{} = adapter) do
          if :dataset in Map.keys(__MODULE__.__struct__()) do
            if dataset = Map.get(adapter, :dataset) do
              {:ok, dataset}
            else
              {:error,
               InvalidEndpointError.exception(
                 "missing :dataset value for store #{inspect(adapter)}"
               )}
            end
          else
            {:ok, ""}
          end
        end
      end

      defoverridable dataset_endpoint_segment: 1

      @impl true
      def handle_sparql(
            %Operation{} = operation,
            %_adapter_type{} = adapter,
            graph_name,
            opts \\ []
          ) do
        GenSPARQL.handle(operation, adapter, graph_name, opts)
      end

      defoverridable handle_sparql: 3, handle_sparql: 4
    end
  end

  @doc """
  Returns the store adapter name for the given store adapter module.

  ## Example

      iex> Gno.Store.Adapter.type_name(Gno.Store.Adapters.Fuseki)
      "Fuseki"

      iex> Gno.Store.Adapter.type_name(Gno.Store.Adapters.Oxigraph)
      "Oxigraph"

      iex> Gno.Store.Adapter.type_name(Gno.Repository)
      ** (RuntimeError) Invalid Gno.Store.Adapter type: Gno.Repository

      iex> Gno.Store.Adapter.type_name(NonExisting)
      ** (RuntimeError) Invalid Gno.Store.Adapter type: NonExisting

  """
  @spec type(type()) :: binary
  def type_name(type) do
    if type?(type) do
      case Module.split(type) do
        ["Gno", "Store", "Adapters", name] -> name
        _ -> raise "Invalid Gno.Store.Adapter type name schema: #{inspect(type)}"
      end
    else
      raise "Invalid Gno.Store.Adapter type: #{inspect(type)}"
    end
  end

  @doc """
  Returns the `Gno.Store.Adapter` module for the given string.

  ## Example

      iex> Gno.Store.Adapter.type("Oxigraph")
      Gno.Store.Adapters.Oxigraph

      iex> Gno.Store.Adapter.type("Commit")
      nil

      iex> Gno.Store.Adapter.type("NonExisting")
      nil

  """
  @spec type(binary) :: type() | nil
  def type(string) when is_binary(string) do
    module = Module.concat(Gno.Store.Adapters, string)

    if type?(module) do
      module
    end
  end

  @doc """
  Checks if the given `module` is a `Gno.Store.Adapter` module.
  """
  @spec type?(module) :: boolean
  def type?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :handle_sparql, 4)
  end
end
