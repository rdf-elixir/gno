defprotocol Gno.Changeset.Action.Graph do
  @moduledoc """
  Protocol for converting data structures to RDF graphs for changeset actions.

  This protocol defines how different data structures can be converted to RDF graphs
  in the context of specific `Gno.Changeset.Action` types.
  """

  @doc """
  Converts the given data structure to an RDF graph for a specific changeset action.

  The action parameter can be one of: `:add`, `:update`, `:replace`, `:remove`, `:overwrite`.
  When action is `nil`, a default conversion is performed.

  Returns `nil` for empty or `nil` inputs, and an `RDF.Graph` for valid inputs.
  """
  @spec graph(t, Gno.Changeset.Action.t()) :: RDF.Graph.t() | nil
  def graph(data, action)
end

defimpl Gno.Changeset.Action.Graph, for: RDF.Graph do
  def graph(graph, _action), do: graph
end

defimpl Gno.Changeset.Action.Graph, for: RDF.Description do
  def graph(description, _action), do: RDF.graph(description)
end

defimpl Gno.Changeset.Action.Graph, for: Tuple do
  def graph(triple, _action), do: RDF.graph(triple)
end

defimpl Gno.Changeset.Action.Graph, for: Atom do
  def graph(nil, _action), do: nil

  def graph(data, _action) do
    raise Protocol.UndefinedError.exception(protocol: @protocol, value: data)
  end
end

defimpl Gno.Changeset.Action.Graph, for: List do
  def graph([], _action), do: nil

  def graph(data, action) do
    Enum.reduce(
      data,
      RDF.graph(),
      &RDF.Graph.add(&2, Gno.Changeset.Action.Graph.graph(&1, action))
    )
  end
end
