defmodule Gno.CommitOperation.Type do
  alias Gno.Commit.Processor

  @type t :: Grax.Schema.t()

  @callback init(Processor.t()) :: {:ok, Processor.t()} | {:error, any()}

  @callback handle_empty_changeset(
              Processor.t(),
              handling :: binary(),
              Gno.EffectiveChangeset.t()
            ) ::
              {:ok, Processor.t()} | {:skip_transaction, Processor.t()} | {:error, any()}

  @doc """
  Returns the commit id under which the commit metadata is stored.
  """
  @callback commit_id(Processor.t()) :: RDF.Resource.t()

  @doc """
  Returns all changes that should be applied in the commit operation.

  This includes the effective changeset and any additional changes that should be
  applied in the same transaction.
  """
  @callback all_changes(Processor.t()) :: %{optional(atom) => any()}

  @doc """
  Adds metadata to the commit operation.

  The metadata is added to the `Processor.metadata` graph from which it is later loaded
  into the `Gno.Commit` object (usually in the final `result/1` callback).
  """
  @callback add_metadata(Processor.t()) :: {:ok, Processor.t()} | {:error, any()}

  @doc """
  Returns the result of the commit operation.
  """
  @callback result(Processor.t()) :: {:ok, any(), Processor.t()} | {:error, any()}

  @doc """
  Prepares the effective changeset from the input changeset.
  """
  @callback prepare_effective_changeset(Processor.t()) :: {:ok, Processor.t()} | {:error, any()}

  @doc """
  Applies the changes to the store.
  """
  @callback apply_changes(Processor.t()) :: {:ok, Processor.t()} | {:error, any()}

  @doc """
  Rolls back changes when an error occurs during the commit process.
  """
  @callback rollback_changes(Processor.t(), state :: atom()) ::
              {:ok, Processor.t()} | {:error, any()}

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
      def init(processor) do
        Gno.CommitOperation.init(processor)
      end

      @impl true
      def commit_id(processor) do
        Gno.CommitOperation.commit_id(processor)
      end

      @impl true
      def all_changes(processor) do
        Gno.CommitOperation.all_changes(processor)
      end

      @impl true
      def add_metadata(processor) do
        Gno.CommitOperation.add_metadata(processor)
      end

      @impl true
      def prepare_effective_changeset(processor) do
        Gno.CommitOperation.prepare_effective_changeset(processor)
      end

      @impl true
      def apply_changes(processor) do
        Gno.CommitOperation.apply_changes(processor)
      end

      @impl true
      def handle_empty_changeset(processor, handling, changeset) do
        Gno.CommitOperation.handle_empty_changeset(processor, handling, changeset)
      end

      @impl true
      def rollback_changes(processor, state) do
        Gno.CommitOperation.rollback_changes(processor, state)
      end

      @impl true
      def result(processor) do
        Gno.CommitOperation.result(processor)
      end

      defoverridable init: 1,
                     commit_id: 1,
                     all_changes: 1,
                     add_metadata: 1,
                     prepare_effective_changeset: 1,
                     apply_changes: 1,
                     handle_empty_changeset: 3,
                     rollback_changes: 2,
                     result: 1
    end
  end
end
