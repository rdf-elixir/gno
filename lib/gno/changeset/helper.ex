defmodule Gno.Changeset.Helper do
  @moduledoc false

  alias Gno.InvalidChangesetError
  alias Gno.Changeset.Action
  alias RDF.{Graph, Dataset}

  def inserts(%{add: add, update: update, replace: replace}) do
    [add, update, replace]
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&Graph.subject_count/1)
    |> case do
      [] -> Graph.new()
      [graph] -> graph
      [largest | rest] -> Enum.reduce(rest, largest, &Graph.add(&2, &1))
    end
  end

  def removals(%{remove: nil}), do: Graph.new()
  def removals(%{remove: remove}), do: remove

  def overwrites(%{overwrite: nil}), do: Graph.new()
  def overwrites(%{overwrite: overwrite}), do: overwrite
  def overwrites(%{}), do: Graph.new()

  def extract(type, keywords) when is_list(keywords) do
    {actions, keywords} = Action.extract(keywords)

    case Keyword.pop(keywords, :changeset) do
      {nil, keywords} ->
        with {:ok, changeset} <- type.new(actions, keywords) do
          {:ok, changeset, keywords}
        end

      {changeset, keywords} ->
        if Action.empty?(actions) do
          with {:ok, changeset} <- to_changeset(type, changeset, keywords) do
            {:ok, changeset, keywords}
          end
        else
          {:error,
           InvalidChangesetError.exception(
             reason: ":changeset can not be used along additional changes"
           )}
        end
    end
  end

  defp to_changeset(type, %type{} = changeset, opts), do: type.validate(changeset, opts)

  defp to_changeset(type, changeset, opts) do
    type
    |> struct!(changeset)
    |> Map.from_struct()
    |> type.new(opts)
  end

  def merged_graph(changeset) do
    changeset
    |> Map.take(Action.fields())
    |> Map.values()
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> Graph.new()
      [graph] -> graph
      [first | graphs] -> Enum.reduce(graphs, first, &Graph.add(&2, &1))
    end
  end

  def action(changeset, triple) do
    Enum.find(Action.fields(), &(changeset |> Map.get(&1) |> graph_include?(triple)))
  end

  def includes?(changeset, subject) do
    Enum.any?(Action.fields(), &(changeset |> Map.get(&1) |> graph_describes?(subject)))
  end

  def subjects(changeset) do
    Enum.reduce(
      Action.fields(),
      MapSet.new(),
      &MapSet.union(&2, changeset |> Map.get(&1) |> graph_subjects())
    )
  end

  def to_rdf(changeset, opts \\ [])

  def to_rdf(%_type{overwrite: overwrite} = changeset, opts) do
    changeset
    |> Map.delete(:overwrite)
    |> to_rdf(opts)
    |> dataset_add(overwrite, graph: Gno.Overwrite)
  end

  def to_rdf(%_type{} = changeset, opts) do
    Dataset.new()
    |> dataset_add(changeset.add, graph: Gno.Addition)
    |> dataset_add(changeset.remove, graph: Gno.Removal)
    |> dataset_add(changeset.update, graph: Gno.Update)
    |> dataset_add(changeset.replace, graph: Gno.Replacement)
    |> dataset_add(opts |> Keyword.get(:prefixes) |> to_rdf_default_graph(), [])
  end

  defp to_rdf_default_graph(prefixes \\ nil)
  defp to_rdf_default_graph(nil), do: Graph.new(prefixes: [gno: Gno])
  defp to_rdf_default_graph(prefixes), do: Graph.add_prefixes(to_rdf_default_graph(), prefixes)

  def from_rdf(%Dataset{} = dataset, type, opts \\ []) do
    type.new!(
      %{
        add: dataset |> Dataset.graph(Gno.Addition) |> reset_name(),
        update: dataset |> Dataset.graph(Gno.Update) |> reset_name(),
        replace: dataset |> Dataset.graph(Gno.Replacement) |> reset_name(),
        remove: dataset |> Dataset.graph(Gno.Removal) |> reset_name(),
        overwrite: dataset |> Dataset.graph(Gno.Overwrite) |> reset_name()
      },
      opts
    )
  end

  def graph_add(nil, additions), do: graph_cleanup(additions)
  def graph_add(graph, nil), do: graph_cleanup(graph)
  def graph_add(graph, additions), do: Graph.add(graph, additions)
  def graph_delete(nil, _), do: nil
  def graph_delete(graph, nil), do: graph_cleanup(graph)
  def graph_delete(graph, removals), do: graph |> Graph.delete(removals) |> graph_cleanup()
  def graph_intersection(nil, _), do: Graph.new()
  def graph_intersection(graph1, graph2), do: Graph.intersection(graph1, graph2)
  def graph_include?(nil, _), do: false
  def graph_include?(graph, triple), do: Graph.include?(graph, triple)
  def graph_describes?(nil, _), do: false
  def graph_describes?(graph, subject), do: Graph.describes?(graph, subject)
  def graph_subjects(nil), do: MapSet.new()
  def graph_subjects(graph), do: Graph.subjects(graph)
  def graph_cleanup(nil), do: nil
  def graph_cleanup(graph), do: unless(Graph.empty?(graph), do: graph)

  defp dataset_add(dataset, nil, _), do: dataset
  defp dataset_add(dataset, additions, opts), do: Dataset.add(dataset, additions, opts)
  defp reset_name(nil), do: nil
  defp reset_name(graph), do: Graph.change_name(graph, nil)
end
