defmodule Gno.CommitLogger do
  @default_log_states ["initializing", "completed"]

  @moduledoc """
  A `Gno.CommitMiddleware` for logging commit operations.

  Logs key commit events and collects log entries from other middlewares
  through the processor's `:log` assign.

  ## Manifest Configuration

      @prefix gno: <http://gno.app/> .

      <Service> a gno:Service
          ; gno:serviceCommitOperation <CommitOperation>
          # ...
      .

      <CommitOperation> a gno:CommitOperation
          ; gno:commitMiddleware ( <Logger> )
      .

      <Logger> a gno:CommitLogger
          ; gno:commitLogLevel "debug"       # optional (default: "info")
          ; gno:commitLogChanges true        # optional (default: false)
          ; gno:commitLogMetadata true       # optional (default: false)
      .

  ## Options

  - `:log_level` (`gno:commitLogLevel`) - the log level to use (default: `"info"`)
  - `:log_states` (`gno:commitLogStates`) - list of states to log; `"all"` logs all
    states, `"none"` logs no state changes (default: `#{inspect(@default_log_states)}`)
  - `:log_changes` (`gno:commitLogChanges`) - whether to log changeset details (default: `false`)
  - `:log_metadata` (`gno:commitLogMetadata`) - whether to log commit metadata (default: `false`)
  """

  use Gno.CommitMiddleware

  alias Gno.Commit.Processor
  require Logger

  def_middleware Gno.CommitLogger do
    property :log_level, Gno.commitLogLevel(), type: :string, default: "info"
    property :log_states, Gno.commitLogStates(), type: list_of(:string)
    property :log_changes, Gno.commitLogChanges(), type: :boolean, default: false
    property :log_metadata, Gno.commitLogMetadata(), type: :boolean, default: false
  end

  @doc """
  Creates a new CommitLogger middleware.

  See module documentation for available options.
  """
  def new(opts \\ []) do
    build(RDF.bnode(), opts)
  end

  def new!(opts \\ []), do: Gno.Utils.bang!(&new/1, [opts])

  @impl true
  def handle_state(state, %__MODULE__{} = middleware, processor) do
    with {:ok, processor} <- process_log_entries(processor, middleware) do
      if should_log_state?(state, middleware), do: log_state(state, processor, middleware)

      {:ok, processor}
    end
  end

  @impl true
  def rollback(%__MODULE__{} = middleware, processor) do
    log_directly(middleware, "Rolling back commit operation", level: "warning")

    process_log_entries(processor, middleware)
  end

  defp should_log_state?(state, middleware) do
    log_states = log_states(middleware)

    "all" in log_states or
      to_string(state) in log_states or
      (state == :prepared && (middleware.log_changes || middleware.log_metadata))
  end

  defp log_states(%__MODULE__{log_states: []}), do: @default_log_states
  defp log_states(%__MODULE__{log_states: log_states}), do: log_states

  defp log_state(:initializing, _, middleware) do
    log_directly(middleware, "Commit operation started")
  end

  defp log_state(:prepared, processor, middleware) do
    if "none" not in log_states(middleware),
      do: log_directly(middleware, "Commit operation prepared")

    if middleware.log_changes && processor.effective_changeset do
      log_directly(
        middleware,
        "Changes:\n#{Gno.Changeset.Formatter.format(processor.effective_changeset, :changes)}"
      )
    end

    if middleware.log_metadata do
      log_directly(middleware, "Metadata:\n#{inspect(processor.metadata)}")
    end

    processor
  end

  defp log_state(:completed, _processor, middleware) do
    log_directly(middleware, "Commit operation completed successfully")
  end

  defp log_state(state, _, middleware) do
    log_directly(middleware, "Commit state: #{state}")
  end

  defp log_directly(middleware, message, opts \\ []) do
    message |> create_entry(opts) |> do_log(middleware)
  end

  @doc """
  Adds a log entry to the processor's log assign.

  ## Options

  - `:level` - The log level (default: "info")
  - `:metadata` - Additional metadata to include in the log
  """
  def log(processor, message, opts \\ []) do
    Processor.assign(processor, :log, [
      create_entry(message, opts) | List.wrap(processor.assigns[:log])
    ])
  end

  defp create_entry(message, opts) do
    %{
      message: message,
      level: Keyword.get(opts, :level),
      metadata: Keyword.get(opts, :metadata, [])
    }
  end

  defp process_log_entries(processor, middleware) do
    (processor.assigns[:log] || [])
    |> Enum.reverse()
    |> Enum.each(&do_log(&1, middleware))

    {:ok, Processor.assign(processor, :log, [])}
  end

  defp do_log(entry, middleware) do
    String.to_existing_atom(entry.level || middleware.log_level)
    |> Logger.log(entry.message, entry.metadata)
  end
end
