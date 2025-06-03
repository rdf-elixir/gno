defmodule Gno.Commit.Processor do
  @moduledoc """
  The central component of the commit operation.

  ```mermaid
  stateDiagram-v2
    [*] --> initializing : init

    %% Pre-Commit Phase
    initializing --> initialized : success
    initializing --> middleware_rollback: fail
    initialized --> preparing : success -> prepare
    initialized --> middleware_rollback: fail
    preparing --> prepared: success
    preparing --> middleware_rollback: fail
    prepared --> starting_transaction: success -> start_transaction
    prepared --> middleware_rollback: fail

    %% Transaction Phase
    starting_transaction --> transaction_started: success
    starting_transaction --> middleware_rollback: fail
    transaction_started --> applying_changes: success -> apply_changes
    transaction_started --> middleware_rollback: fail
    applying_changes --> changes_applied: success
    applying_changes --> middleware_rollback: fail
    changes_applied --> ending_transaction: success -> end_transaction
    changes_applied --> rollback: fail
    ending_transaction --> transaction_ended: success
    ending_transaction --> rollback: fail

    %% Post-Commit Phase
    transaction_ended --> executing_post_commit: success -> post_commit
    transaction_ended --> rollback: fail
    executing_post_commit --> completed: success
    executing_post_commit --> error: fail
    completed --> [*]

    %% Rollback Phase
    rollback --> middleware_rollback: success
    rollback --> critical_error: fail
    middleware_rollback --> error: success
    middleware_rollback --> critical_error: fail

    %% Error States
    error --> [*]
    critical_error --> [*]

    state pre-commit {
        initializing
        initialized
        preparing
        prepared
    }
    state commit-transaction {
        starting_transaction
        transaction_started
        applying_changes
        changes_applied
        ending_transaction
        transaction_ended
    }
    state post-commit {
        executing_post_commit
        completed
    }
  ```
  """

  alias Gno.Service
  alias Gno.Commit.{ProcessorError, ProcessorRollbackError}
  alias Gno.{CommitMiddleware, Changeset, EffectiveChangeset}
  alias RDF.Graph

  defstruct service: nil,
            state: nil,
            input: nil,
            input_options: nil,
            middlewares: [],
            changeset: nil,
            effective_changeset: nil,
            sparql_update: nil,
            commit_id: nil,
            additional_changes: %{},
            metadata: Graph.new(),
            assigns: %{},
            errors: []

  @type state ::
          nil
          | :initializing
          | :initialized
          | :preparing
          | :prepared
          | :starting_transaction
          | :transaction_started
          | :applying_changes
          | :changes_applied
          | :ending_transaction
          | :transaction_ended
          | :executing_post_commit
          | :completed
          | :rollback

  @type assigns :: %{optional(atom) => any}

  @type t :: %__MODULE__{
          service: Service.t(),
          state: state(),
          input: any(),
          input_options: keyword(),
          middlewares: [CommitMiddleware.t()],
          changeset: Gno.Changeset.t(),
          effective_changeset: Gno.EffectiveChangeset.t(),
          sparql_update: Update.t(),
          commit_id: RDF.Resource.t(),
          additional_changes: %{optional(atom) => any()},
          metadata: Graph.t(),
          assigns: assigns(),
          errors: [any()]
        }

  @activity_states %{
    init: {:initializing, :initialized},
    preparation: {:preparing, :prepared},
    start_transaction: {:starting_transaction, :transaction_started},
    apply_changes: {:applying_changes, :changes_applied},
    end_transaction: {:ending_transaction, :transaction_ended},
    post_commit: {:executing_post_commit, :completed}
  }

  @rollback_update_states [
    :changes_applied,
    :ending_transaction
  ]

  @no_rollback_states [
    :transaction_ended,
    :executing_post_commit,
    :completed
  ]

  import Gno.Utils, only: [bang!: 2]

  def new(service) do
    {:ok,
     %__MODULE__{service: service, middlewares: List.wrap(service.commit_operation.middlewares)}}
  end

  def new!(service), do: bang!(&new/1, [service])

  def execute(%__MODULE__{} = processor, input, opts \\ []) do
    processor = %{processor | input: input, input_options: opts}

    with {:ok, processor} <-
           (case pre_commit(processor) do
              {:skip_transaction, processor} -> {:ok, processor}
              {:ok, processor} -> commit(processor)
              {:error, _} = error -> error
            end) do
      post_commit(processor)
    end
  end

  defp pre_commit(processor) do
    with {:ok, processor} <- execute_activity(processor, :init, &operation_type(&1).init(&1)),
         {:ok, processor} <-
           execute_activity(processor, :preparation, fn processor ->
             with {:ok, processor} <-
                    operation_type(processor).prepare_effective_changeset(processor),
                  {:ok, processor} <- operation_type(processor).add_metadata(processor) do
               {:ok, processor}
             end
           end) do
      handle_empty_changeset(processor)
    end
  end

  defp commit(processor) do
    with {:ok, processor} <- execute_activity(processor, :start_transaction),
         {:ok, processor} <-
           execute_activity(processor, :apply_changes, &operation_type(&1).apply_changes(&1)),
         {:ok, processor} <- execute_activity(processor, :end_transaction) do
      {:ok, processor}
    end
  end

  defp post_commit(processor) do
    with {:ok, processor} <- execute_activity(processor, :post_commit) do
      operation_type(processor).result(processor)
    end
  end

  defp execute_activity(processor, activity, activity_fn \\ nil) do
    {executing_state, completed_state} = @activity_states[activity]

    case run_middleware(processor, executing_state) do
      {:ok, processor} ->
        processor = %{processor | state: executing_state}

        with {:ok, processor} <- apply_activity_fun(processor, activity_fn),
             {:ok, processor} <- run_middleware(processor, completed_state) do
          {:ok, %{processor | state: completed_state}}
        else
          {:error, reason} -> handle_error(processor, reason)
          {:error, reason, processor} -> handle_error(processor, reason)
        end

      {:error, reason, processor} ->
        handle_error(processor, reason)
    end
  end

  defp apply_activity_fun(processor, nil), do: {:ok, processor}
  defp apply_activity_fun(processor, activity_fn), do: activity_fn.(processor)

  defp run_middleware(processor, state) do
    Enum.reduce(processor.middlewares, {:ok, processor, []}, fn
      %{state: old_state} = middleware, {:ok, processor, updated_middlewares} ->
        case apply_middleware(middleware, :handle_state, [state, middleware, processor]) do
          {:ok, updated_processor} ->
            {:ok, updated_processor,
             [CommitMiddleware.set_state(middleware, state) | updated_middlewares]}

          {:ok, updated_processor, updated_middleware} ->
            {
              :ok,
              updated_processor,
              [
                CommitMiddleware.set_state(updated_middleware, state, old_state)
                | updated_middlewares
              ]
            }

          {:error, error} ->
            {:error, error, processor, [middleware | updated_middlewares]}

          {:error, error, updated_processor} ->
            {:error, error, updated_processor, [middleware | updated_middlewares]}
        end

      middleware, {:error, error, processor, updated_middlewares} ->
        {:error, error, processor, [middleware | updated_middlewares]}
    end)
    |> case do
      {:ok, processor, middlewares} ->
        {:ok, %{processor | middlewares: Enum.reverse(middlewares)}}

      {:error, error, processor, middlewares} ->
        {:error, error, %{processor | middlewares: Enum.reverse(middlewares)}}
    end
  end

  defp apply_middleware(%middleware_type{}, function, args) do
    apply(middleware_type, function, args)
  rescue
    exception -> {:error, exception}
  end

  defp handle_empty_changeset(
         %__MODULE__{effective_changeset: %Gno.NoEffectiveChanges{} = changeset} = processor
       ) do
    operation_type(processor).handle_empty_changeset(
      processor,
      Keyword.get(
        processor.input_options,
        :on_no_effective_changes,
        operation(processor).on_no_effective_changes
      ),
      changeset
    )
  end

  defp handle_empty_changeset(processor), do: {:ok, processor}

  defp handle_error(%__MODULE__{state: state} = processor, error)
       when state not in @no_rollback_states do
    processor = %{processor | state: {:rollback, state}} |> add_error(error)

    case perform_rollback(processor, state) do
      {:ok, processor} ->
        {:error, ProcessorError.exception(processor: processor)}

      {:error, rollback_error} ->
        {:error, ProcessorRollbackError.exception(processor: processor, error: rollback_error)}

      {:error, rollback_error, processor} ->
        {:error, ProcessorRollbackError.exception(processor: processor, error: rollback_error)}
    end
  end

  defp handle_error(processor, error) do
    {:error, ProcessorError.exception(processor: add_error(processor, error))}
  end

  defp perform_rollback(processor, state) do
    with {:ok, processor} <- rollback_changes(processor, state),
         {:ok, processor} <- run_middleware_rollback(processor) do
      {:ok, %{processor | state: {:rolled_back, state}}}
    end
  end

  defp rollback_changes(processor, state) when state in @rollback_update_states do
    operation_type(processor).rollback_changes(processor, state)
  end

  defp rollback_changes(processor, _state), do: {:ok, processor}

  defp run_middleware_rollback(processor) do
    {processor, middlewares, errors} =
      Enum.reduce(processor.middlewares, {processor, [], []}, fn
        middleware, {processor, updated_middlewares, errors} ->
          case apply_middleware(middleware, :rollback, [middleware, processor]) do
            {:ok, updated_processor} ->
              {updated_processor, [middleware | updated_middlewares], errors}

            {:ok, updated_processor, updated_middleware} ->
              {updated_processor, [updated_middleware | updated_middlewares], errors}

            {:error, error} ->
              {processor, [middleware | updated_middlewares], [error | errors]}

            {:error, error, updated_processor} ->
              {updated_processor, [middleware | updated_middlewares], [error | errors]}
          end
      end)

    processor = %{processor | middlewares: Enum.reverse(middlewares)}

    case errors do
      [] -> {:ok, processor}
      [error] -> {:error, error, processor}
      errors -> {:error, errors, processor}
    end
  end

  def operation_type(%__MODULE__{service: %{commit_operation: %operation_type{}}}),
    do: operation_type

  def operation(%__MODULE__{service: %{commit_operation: operation}}), do: operation

  def commit_id(processor), do: operation_type(processor).commit_id(processor)

  def update_commit_id(%__MODULE__{commit_id: nil} = processor, commit_id) do
    %{processor | commit_id: commit_id}
  end

  def update_commit_id(processor, commit_id) do
    %{
      processor
      | commit_id: commit_id,
        metadata: Graph.rename_resource(processor.metadata, processor.commit_id, commit_id)
    }
  end

  def update_metadata(%__MODULE__{} = processor, %Graph{} = metadata) do
    {:ok, %__MODULE__{processor | metadata: metadata}}
  end

  def update_metadata(%__MODULE__{metadata: graph} = processor, fun) when is_function(fun) do
    case fun.(graph) do
      %Graph{} = new_graph -> update_metadata(processor, new_graph)
      {:ok, %Graph{} = new_graph} -> update_metadata(processor, new_graph)
      {:error, _} = error -> error
    end
  end

  def update_metadata!(processor, graph_or_fun),
    do: bang!(&update_metadata/2, [processor, graph_or_fun])

  def add_additional_changes(%__MODULE__{} = processor, graph_name, changes) do
    {:ok,
     %__MODULE__{
       processor
       | additional_changes:
           add_additional_changes(processor.additional_changes, graph_name, changes)
     }}
  end

  def add_additional_changes(additional_changes, graph_name, changes) do
    Map.update(
      additional_changes,
      graph_name,
      normalize_changes(changes),
      &update_existing_changes(&1, changes)
    )
  end

  defp normalize_changes(%EffectiveChangeset{} = effective_changeset), do: effective_changeset
  defp normalize_changes(changes), do: Changeset.new!(changes)

  defp update_existing_changes(%Changeset{} = existing, changes) do
    Changeset.update(existing, normalize_changes(changes))
  end

  defp update_existing_changes(%EffectiveChangeset{} = existing, changes) do
    existing |> Changeset.new!() |> Changeset.update(normalize_changes(changes))
  end

  def all_changes(processor) do
    operation_type(processor).all_changes(processor)
  end

  def assign(processor, key, value) do
    put_in(processor.assigns[key], value)
  end

  def add_error(processor, error) do
    %{processor | errors: [error | processor.errors]}
  end
end
