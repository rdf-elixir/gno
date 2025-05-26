defmodule Gno.CommitMiddleware do
  use Grax.Schema

  schema Gno.CommitMiddleware do
    field :state
  end

  @type type :: module

  @callback handle_state(state :: atom(), t(), Processor.t()) ::
              {:ok, Processor.t()}
              | {:ok, Processor.t(), t()}
              | {:error, term()}
              | {:error, term(), Processor.t()}

  @callback rollback(t(), Processor.t()) ::
              {:ok, Processor.t()}
              | {:ok, Processor.t(), t()}
              | {:error, term()}
              | {:error, term(), Processor.t()}

  defmacro __using__(_opts) do
    quote do
      @behaviour unquote(__MODULE__)
      import unquote(__MODULE__), only: [def_middleware: 2]
    end
  end

  defmacro def_middleware(class, do: block) do
    quote do
      use Grax.Schema

      schema unquote(class) < Gno.CommitMiddleware do
        unquote(block)
      end

      @impl true
      def handle_state(_state, %__MODULE__{} = middleware, processor),
        do: {:ok, middleware}

      @impl true
      def rollback(%__MODULE__{} = middleware, processor), do: {:ok, middleware}

      defoverridable handle_state: 3, rollback: 2
    end
  end

  def set_state(middleware, state, from_state \\ nil) do
    if is_nil(from_state) || middleware.state == from_state do
      %{middleware | state: state}
    else
      middleware
    end
  end

  @doc """
  Checks if the given `module` is a `Gno.CommitMiddleware`.

  ## Example

      iex> Gno.CommitMiddleware.type?(Gno.CommitLogger)
      true

      iex> Gno.CommitMiddleware.type?(Gno.Commit)
      false

      iex> Gno.CommitMiddleware.type?(NonExisting)
      false

  """
  @spec type?(module) :: boolean
  def type?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :handle_state, 3)
  end

  def type?(%RDF.IRI{} = iri), do: iri |> Grax.schema() |> type?()
  def type?(_), do: false

  def type(%RDF.IRI{} = iri) do
    schema = Grax.schema(iri)

    if type?(schema) do
      schema
    end
  end

  def type(_), do: nil
end
