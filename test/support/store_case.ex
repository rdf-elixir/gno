defmodule Gno.StoreCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use GnoCase, async: false

      import unquote(__MODULE__)

      setup :clean_store!
    end
  end

  def clean_store!(_) do
    :ok = Gno.drop(:all)
  end

  def fuseki_available?(store) do
    Gno.Store.Adapters.Fuseki.ping?(store)
  end

  def without_prefixes({:ok, value}) do
    {:ok, without_prefixes(value)}
  end

  def without_prefixes(%Gno.Commit{} = commit) do
    %Gno.Commit{commit | changeset: without_prefixes(commit.changeset)}
  end

  def without_prefixes(%Gno.EffectiveChangeset{} = changeset) do
    %Gno.EffectiveChangeset{
      changeset
      | add: without_prefixes(changeset.add),
        update: without_prefixes(changeset.update),
        replace: without_prefixes(changeset.replace),
        remove: without_prefixes(changeset.remove),
        overwrite: without_prefixes(changeset.overwrite)
    }
  end

  def without_prefixes(%RDF.Graph{} = graph) do
    RDF.Graph.clear_prefixes(graph)
  end

  def without_prefixes(nil), do: nil
end
