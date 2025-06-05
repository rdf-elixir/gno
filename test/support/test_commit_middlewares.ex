defmodule TestStateFlowMiddleware do
  @moduledoc """
  A test `Gno.CommitMiddleware` that records the state flow in the metadata graph.
  """

  use Gno.CommitMiddleware

  alias Gno.Commit.Processor
  alias Gno.CommitLogger
  alias RDF.Graph
  alias Gno.TestNamespaces.EX
  @compile {:no_warn_undefined, Gno.TestNamespaces.EX}

  def_middleware EX.TestStateFlowMiddleware do
    property :label, RDF.NS.RDFS.label(), type: :string, default: "default"
    property :custom_log_message, EX.customLogMessage(), type: :string
    field :fail_on_state
    field :fail_type
  end

  @state_flow_list_property EX.stateFlow()

  def new(label \\ "default", args \\ []) do
    with {:ok, middleware} <- build(RDF.bnode(), args) do
      Grax.put(middleware, :label, label)
    end
  end

  def new!(label \\ "default", args \\ []), do: Gno.Utils.bang!(&new/2, [label, args])

  @impl true
  def handle_state(fail_state, %__MODULE__{fail_on_state: fail_state} = middleware, _processor) do
    fail(middleware, fail_state)
  end

  def handle_state(
        fail_state,
        %__MODULE__{fail_on_state: {:rollback, fail_state}} = middleware,
        _processor
      ) do
    fail(middleware, fail_state)
  end

  def handle_state(state, %__MODULE__{} = middleware, processor) do
    processor =
      if middleware.custom_log_message do
        CommitLogger.log(processor, middleware.custom_log_message)
      else
        processor
      end

    if Processor.commit_id(processor) do
      prepend_state_flow(processor, middleware, state)
    else
      {:ok, processor}
    end
  end

  @impl true
  def rollback(%__MODULE__{fail_on_state: {:rollback, _}} = middleware, processor) do
    fail(middleware, processor.state)
  end

  def rollback(middleware, %Processor{state: {:rollback, state}} = processor) do
    prepend_state_flow(processor, middleware, "rollback-#{state}")
  end

  defp fail(middleware, {:rollback, state}) do
    fail(middleware, "rollback of #{state}")
  end

  defp fail(middleware, state) do
    case middleware.fail_type || :error do
      :error -> {:error, "Failed on state #{state}"}
      :exception -> raise "Failed on state #{state}"
    end
  end

  def state_value(middleware, state),
    do: "#{state}-#{middleware.label}-mw_state:#{middleware.state}"

  def state_flow_list(processor) do
    case state_flow_list_head(processor) do
      nil -> RDF.List.from([])
      [head_id] -> RDF.List.new(head_id, processor.metadata)
    end
  end

  def state_flow_list_head(processor) do
    get_in(processor.metadata, [Processor.commit_id(processor), @state_flow_list_property])
  end

  def prepend_state_flow(processor, middleware, state) do
    Processor.update_metadata(processor, fn graph ->
      new_list =
        processor
        |> state_flow_list()
        |> RDF.List.prepend(state_value(middleware, state))

      graph
      |> Graph.put_properties(new_list.graph)
      |> Graph.put_properties(
        {Processor.commit_id(processor), @state_flow_list_property, new_list.head}
      )
    end)
  end
end
