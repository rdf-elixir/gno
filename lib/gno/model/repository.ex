defmodule Gno.Repository do
  use Grax.Schema

  alias RDF.IRI

  import Gno.Utils, only: [bang!: 2]

  schema Gno.Repository do
    link dataset: Gno.repositoryDataset(), type: Gno.Dataset, required: true
  end

  def new(id, attrs) do
    build(id, attrs)
  end

  def new!(id, attrs), do: bang!(&new/2, [id, attrs])

  def dataset_graph_id(%{dataset: %{__id__: dataset_id}}), do: dataset_id

  def graph_id(%{__id__: repository_id}), do: repository_id

  def graph_id(_repository, nil), do: nil
  def graph_id(_repository, :all), do: :all
  def graph_id(_repository, %IRI{} = graph_name), do: graph_name
  def graph_id(_repository, graph_name) when is_binary(graph_name), do: RDF.iri(graph_name)
  def graph_id(repository, :repo), do: graph_id(repository)
  def graph_id(repository, :dataset), do: dataset_graph_id(repository)

  # for now we assume that the graph name is the same as the graph id
  def graph_name(repository, graph_id) do
    graph_id(repository, graph_id)
  end
end
