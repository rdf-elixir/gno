defmodule Gno.Commit.Update do
  @moduledoc false

  alias Gno.{Repository, Changeset, EffectiveChangeset}
  alias RDF.NTriples

  @type changes :: Changeset.t() | EffectiveChangeset.t()
  @type graph_changes :: %{optional(atom() | String.t()) => changes()}

  @doc """
  Builds a SPARQL update operation for the given changes.
  """
  @spec build(Repository.t(), graph_changes()) :: Gno.Store.SPARQL.Operation.t()
  def build(repo, additional_changes) do
    """
    DELETE DATA {
      #{Enum.map_join(additional_changes, "\n", fn {graph_name, changes} -> graph_changes(repo, graph_name, deletes(changes)) end)}
    } ;
    INSERT DATA {
      #{Enum.map_join(additional_changes, "\n", fn {graph_name, changes} -> graph_changes(repo, graph_name, inserts(changes)) end)}
    }
    """
    |> Gno.Store.SPARQL.Operation.update()
  end

  @doc """
  Builds a SPARQL update operation for reverting the given changes.
  """
  def build_revert(repo, additional_changes) do
    build(repo, invert(additional_changes))
  end

  defp deletes(%Changeset{} = changeset), do: Changeset.deletes(changeset)
  defp deletes(%EffectiveChangeset{} = changeset), do: EffectiveChangeset.deletes(changeset)

  defp inserts(%Changeset{} = changeset), do: Changeset.inserts(changeset)
  defp inserts(%EffectiveChangeset{} = changeset), do: EffectiveChangeset.inserts(changeset)

  defp invert(additional_changes) do
    Map.new(additional_changes, fn {graph_name, changes} -> {graph_name, do_invert(changes)} end)
  end

  defp do_invert(%EffectiveChangeset{} = changeset), do: EffectiveChangeset.invert(changeset)
  defp do_invert(%Changeset{} = changeset), do: Changeset.invert(changeset)

  defp graph_changes(_repo, _graph_id, nil), do: ""

  defp graph_changes(repo, graph_name, changes) do
    "GRAPH <#{Repository.graph_name(repo, graph_name)}> { #{triples(changes)} }"
  end

  defp triples(nil), do: ""
  defp triples(data), do: NTriples.write_string!(data)
end
