defmodule Gno.CommitMiddleware do
  @moduledoc """
  Behaviour for pluggable components in the `Gno.Commit.Processor` pipeline.

  The processor calls `c:handle_state/3` on each middleware at every state
  transition (see the state machine in `Gno.Commit.Processor`). The callback
  receives the new state atom, the middleware struct, and the processor, and
  must return `{:ok, processor}` (optionally with an updated middleware) or
  an error tuple to abort. On failure, `c:rollback/2` is called on all
  middlewares that were already invoked.

  The `:state` field on the middleware struct tracks the last state it was
  called with, managed automatically by the processor.

  ## Defining a Middleware

  Use `def_middleware/2` to define a Grax schema subclassing this module:

      defmodule MyMiddleware do
        use Gno.CommitMiddleware

        def_middleware MyNS.MyMiddleware do
          property :my_option, type: :string
        end

        @impl true
        def handle_state(:initialized, middleware, processor) do
          # custom logic
          {:ok, processor}
        end
      end

  Middlewares are configured in the `Gno.CommitOperation` of a `Gno.Service`.
  See `Gno.CommitLogger` for a built-in example.
  """

  use Grax.Schema

  alias Gno.Commit.Processor

  schema Gno.CommitMiddleware do
    field :state
  end

  @type type :: module
  @type middleware :: %{
          :__struct__ => type(),
          :__id__ => term(),
          :state => term(),
          optional(atom()) => term()
        }

  @callback handle_state(state :: atom(), middleware(), Processor.t()) ::
              {:ok, Processor.t()}
              | {:ok, Processor.t(), middleware()}
              | {:error, term()}
              | {:error, term(), Processor.t()}

  @callback rollback(middleware(), Processor.t()) ::
              {:ok, Processor.t()}
              | {:ok, Processor.t(), middleware()}
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
        do: {:ok, processor}

      @impl true
      def rollback(%__MODULE__{} = middleware, processor), do: {:ok, processor}

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

  @doc """
  Returns the middleware module for the given IRI, or `nil` if not a middleware.
  """
  def type(%RDF.IRI{} = iri) do
    schema = Grax.schema(iri)

    if type?(schema) do
      schema
    end
  end

  def type(_), do: nil
end
