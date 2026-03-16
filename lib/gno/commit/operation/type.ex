defmodule Gno.CommitOperation.Type do
  @moduledoc """
  Behaviour for custom commit operation types.

  A custom commit operation type can be defined by implementing this behaviour and using the `use Gno.CommitOperation.Type` macro.

  This provides a macro `def_commit_operation/2` that can be used to define the
  Grax schema of the commit operation.
  The schema should only define properties for configuration that is loaded from
  the RDF manifest. Runtime state belongs on the `Gno.Commit.Processor` (via
  `assigns`, `metadata`, etc.), so that middlewares can access it.
  """
  alias Gno.Commit.Processor

  @type t :: Grax.Schema.t()

  @doc """
  Handles state transitions during the commit process.
  """
  @callback handle_step(step :: atom(), Processor.t()) ::
              {:ok, Processor.t()}
              | {:error, term()}
              | {:error, term(), Processor.t()}

  @doc """
  Handles the case that no effective changes result from the changeset.

  Implementations can in particular implement custom handling of the
  `:on_no_effective_changes` option with additional `handling` values.
  """
  @callback handle_empty_changeset(
              Processor.t(),
              handling :: binary(),
              Gno.EffectiveChangeset.t()
            ) ::
              {:ok, Processor.t()} | {:skip_transaction, Processor.t()} | {:error, any()}

  @doc """
  Rolls back changes when an error occurs during the commit process.
  """
  @callback rollback(state :: atom(), Processor.t()) ::
              {:ok, Processor.t()}
              | {:error, term()}
              | {:error, term(), Processor.t()}

  @doc """
  Prepares the final commit and adding its metadata.

  Note, that this callback is called by the default implementation of the `handle_step/2` of
  the `:preparation` step, allowing its customization. So, it is only needed when this
  default implementation is reused.
  """
  @callback prepare_commit(Processor.t()) :: {:ok, Processor.t()} | {:error, any()}

  @doc """
  Returns all changes that should be applied in the commit operation.

  This includes the effective changeset and any additional changes that should be
  applied in the same transaction.
  """
  @callback all_changes(Processor.t()) :: %{optional(atom) => any()}

  @doc """
  Returns the result of the commit operation.
  """
  @callback result(Processor.t()) :: {:ok, any(), Processor.t()} | {:error, any()}

  defmacro __using__(_opts) do
    quote do
      @behaviour unquote(__MODULE__)
      import unquote(__MODULE__), only: [def_commit_operation: 2]
    end
  end

  defmacro def_commit_operation(class, do: block) do
    quote do
      use Grax.Schema

      schema unquote(class) < Gno.CommitOperation do
        unquote(block)
      end

      def on_load(operation, graph, opts) do
        Gno.CommitOperation.on_load(operation, graph, opts)
      end

      @impl true
      def handle_step(step, processor) do
        Gno.CommitOperation.handle_step(step, processor)
      end

      @impl true
      def handle_empty_changeset(processor, handling, changeset) do
        Gno.CommitOperation.handle_empty_changeset(processor, handling, changeset)
      end

      @impl true
      def rollback(state, processor) do
        Gno.CommitOperation.rollback(state, processor)
      end

      @impl true
      def all_changes(processor) do
        Gno.CommitOperation.all_changes(processor)
      end

      @impl true
      def prepare_commit(processor) do
        Gno.CommitOperation.prepare_commit(processor)
      end

      @impl true
      def result(processor) do
        Gno.CommitOperation.result(processor)
      end

      defoverridable handle_step: 2,
                     handle_empty_changeset: 3,
                     rollback: 2,
                     all_changes: 1,
                     prepare_commit: 1,
                     result: 1
    end
  end
end
