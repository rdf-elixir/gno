defmodule Gno.Commit.Update do
  @moduledoc false

  alias Gno.{Service, Changeset, EffectiveChangeset}
  alias RDF.NTriples

  @type changes :: Changeset.t() | EffectiveChangeset.t()
  @type graph_changes :: %{optional(atom() | String.t()) => changes()}

  @doc """
  Builds a SPARQL update operation for the given changes.
  """
  @spec build(Service.t(), graph_changes()) :: Gno.Store.SPARQL.Operation.t()
  def build(service, additional_changes) do
    """
    DELETE DATA {
      #{Enum.map_join(additional_changes, "\n", fn {graph_name, changes} -> graph_changes(service, graph_name, deletes(changes)) end)}
    } ;
    INSERT DATA {
      #{Enum.map_join(additional_changes, "\n", fn {graph_name, changes} -> graph_changes(service, graph_name, inserts(changes)) end)}
    }
    """
    |> Gno.Store.SPARQL.Operation.update()
  end

  @doc """
  Builds a SPARQL update operation for reverting the given changes.
  """
  def build_revert(service, additional_changes) do
    build(service, invert(additional_changes))
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

  defp graph_changes(_service, _graph_id, nil), do: ""
  defp graph_changes(_service, :default, changes), do: triples(changes)

  defp graph_changes(%service_type{} = service, graph_name, changes) do
    case service_type.graph_name(service, graph_name) do
      :default -> triples(changes)
      resolved_graph_name -> "GRAPH <#{resolved_graph_name}> { #{triples(changes)} }"
    end
  end

  defp triples(nil), do: ""
  defp triples(data), do: NTriples.write_string!(data)
end
