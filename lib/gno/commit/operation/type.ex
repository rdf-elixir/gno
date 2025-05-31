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

  @callback commit_id(Processor.t()) :: {:ok, RDF.Resource.t()} | {:error, any()}

  @callback add_metadata(Processor.t()) :: {:ok, Processor.t()} | {:error, any()}

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
      def init(processor) do
        Gno.CommitOperation.init(processor)
      end

      @impl true
      def handle_empty_changeset(processor, handling, changeset) do
        Gno.CommitOperation.handle_empty_changeset(processor, handling, changeset)
      end

      @impl true
      def commit_id(processor) do
        Gno.CommitOperation.commit_id(processor)
      end

      @impl true
      def add_metadata(processor) do
        Gno.CommitOperation.add_metadata(processor)
      end

      @impl true
      def result(processor) do
        Gno.CommitOperation.result(processor)
      end

      defoverridable init: 1,
                     handle_empty_changeset: 3,
                     commit_id: 1,
                     add_metadata: 1,
                     result: 1
    end
  end
end
