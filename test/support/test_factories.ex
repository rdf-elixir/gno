defmodule Gno.TestFactories do
  @moduledoc """
  Test factories.
  """

  use RDF

  alias Gno.{Changeset, EffectiveChangeset, Commit, CommitOperation}
  alias RDF.Graph

  alias Gno.TestNamespaces.EX
  @compile {:no_warn_undefined, Gno.TestNamespaces.EX}

  def id(:repo_manifest), do: ~I<http://example.com/test/repository_manifest>
  def id(:alt_repo_manifest), do: ~I<http://example.com/test/alt_repository_manifest>
  def id(:dataset), do: ~I<http://example.com/test/dataset>
  def id(:alt_dataset), do: ~I<http://example.com/test/alt_dataset>
  def id(resource) when is_rdf_resource(resource), do: resource
  def id(iri) when is_binary(iri), do: RDF.iri(iri)

  def datetime, do: ~U[2023-05-26 13:02:02.255559Z]

  def datetime(amount_to_add, unit \\ :second),
    do: datetime() |> DateTime.add(amount_to_add, unit)

  def statement(id) when is_integer(id) or is_atom(id) do
    {
      apply(EX, :"s#{id}", []),
      apply(EX, :"p#{id}", []),
      apply(EX, :"o#{id}", [])
    }
  end

  def statement({id1, id2})
      when (is_integer(id1) or is_atom(id1)) and (is_integer(id2) or is_atom(id2)) do
    {
      apply(EX, :"s#{id1}", []),
      apply(EX, :"p#{id2}", []),
      apply(EX, :"o#{id2}", [])
    }
  end

  def statement({id1, id2, id3} = triple)
      when (is_integer(id1) or is_atom(id1)) and
             (is_integer(id2) or is_atom(id2)) and
             (is_integer(id3) or is_atom(id3)) do
    if RDF.Triple.valid?(triple) do
      triple
    else
      {
        apply(EX, :"s#{id1}", []),
        apply(EX, :"p#{id2}", []),
        apply(EX, :"o#{id3}", [])
      }
    end
  end

  def statement(statement), do: statement

  def statements(statements) when is_list(statements) do
    Enum.flat_map(statements, fn
      statement when is_integer(statement) or is_atom(statement) or is_tuple(statement) ->
        [statement(statement)]

      statement ->
        statement |> RDF.graph() |> Graph.statements()
    end)
  end

  def empty_graph, do: RDF.graph()

  @graph [
           EX.S1 |> EX.p1(EX.O1),
           EX.S2 |> EX.p2(42, "Foo")
         ]
         |> RDF.graph()
  def graph, do: @graph

  def graph(statements, opts \\ [])

  def graph(statement, opts) when is_integer(statement) or is_atom(statement) do
    statement |> statement() |> RDF.graph(opts)
  end

  def graph(statements, opts) when is_list(statements) do
    statements |> statements() |> RDF.graph(opts)
  end

  def graph(other, opts) do
    RDF.graph(other, opts)
  end

  @subgraph [
              EX.S1 |> EX.p1(EX.O1)
            ]
            |> RDF.graph()
  def subgraph, do: @subgraph

  def alt_service(service, attrs \\ []) do
    repo_id = Keyword.get(attrs, :repo_id, :alt_repo_manifest)
    dataset_id = Keyword.get(attrs, :dataset_id, :alt_dataset)
    store = Keyword.get(attrs, :store, service.store)

    %{
      service
      | repository: %{
          service.repository
          | __id__: id(repo_id),
            dataset: %{service.repository.dataset | __id__: id(dataset_id)}
        },
        store: store
    }
  end

  def single_graph_service(service, attrs \\ []) do
    repo_id = Keyword.get(attrs, :repo_id, :alt_repo_manifest)
    store = Keyword.get(attrs, :store, service.store)
    primary_graph = service.repository.primary_graph

    %{
      service
      | repository: %{
          service.repository
          | __id__: id(repo_id),
            dataset: nil,
            data_graph: primary_graph,
            primary_graph: primary_graph
        },
        store: store
    }
  end

  def unavailable_fuseki do
    Gno.Store.Adapters.Fuseki.build!(
      ~I<http://example.com/UnreachableFuseki>,
      host: "unreachable.example.com",
      port: 9999,
      dataset: "unreachable-dataset"
    )
  end

  def fuseki_store(dataset_name \\ "test-dataset") do
    Gno.Store.Adapters.Fuseki.build!(~I<http://example.com/TestFuseki>, dataset: dataset_name)
  end

  def changeset_attrs(attrs \\ []) do
    [
      add: graph(),
      remove: {EX.Foo, EX.bar(), 42}
    ]
    |> Keyword.merge(attrs)
  end

  def changeset(attrs \\ []) do
    attrs
    |> changeset_attrs()
    |> Changeset.new!()
  end

  def effective_changeset(attrs \\ []) do
    attrs
    |> changeset_attrs()
    |> EffectiveChangeset.new!()
  end

  def commit_operation(type, attrs \\ [])

  def commit_operation(attrs, []) when is_list(attrs) do
    {type, attrs} = Keyword.pop(attrs, :commit_operation, CommitOperation)
    commit_operation(type, attrs)
  end

  def commit_operation(type, attrs) when is_atom(type) do
    commit_operation(Gno.Service.default_commit_operation(type), attrs)
  end

  def commit_operation(%_{} = commit_operation, attrs) do
    Grax.put!(commit_operation, attrs)
  end

  def service(attrs \\ []) do
    %{Gno.Manifest.service!() | commit_operation: commit_operation(attrs)}
  end

  def commit_processor(attrs \\ []) do
    Commit.Processor.new!(service(attrs))
  end

  def test_commit_processor(attrs \\ []) do
    attrs
    |> Keyword.put(:commit_operation, TestCommitOperation)
    |> commit_processor()
  end
end
