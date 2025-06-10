defmodule GnoTest do
  use Gno.StoreCase
  doctest Gno

  test "operation helpers" do
    assert Gno.ask("ASK { ?s ?p ?o }") == {:ok, false}

    assert [
             {EX.s1(), EX.p1(), "Object 1"},
             {EX.s1(), EX.p2(), EX.o2()},
             {EX.s2(), EX.p1(), "Object 2"}
           ]
           |> RDF.graph()
           |> Gno.insert_data() == :ok

    assert Gno.ask!("ASK { <#{EX.s1()}> <#{EX.p2()}> <#{EX.o2()}> . }")

    assert {:ok, %SPARQL.Query.Result{results: results}} =
             Gno.select("""
             SELECT ?s ?o
             WHERE { ?s <#{EX.p1()}> ?o }
             ORDER BY ?o
             """)

    assert results == [
             %{"s" => EX.s1(), "o" => ~L"Object 1"},
             %{"s" => EX.s2(), "o" => ~L"Object 2"}
           ]

    assert Gno.update("""
             WITH <#{Gno.graph_name(:dataset)}>
             DELETE { ?s <#{EX.p1()}> "Object 1" }
             INSERT { ?s <#{EX.p1()}> "Updated Object" }
             WHERE  { ?s <#{EX.p1()}> "Object 1" }
           """) == :ok

    refute Gno.ask!(~s(ASK { ?s <#{EX.p1()}> "Object 1" }))
    assert Gno.ask!(~s(ASK { ?s <#{EX.p1()}> "Updated Object" }))

    assert RDF.graph([{EX.s2(), EX.p1(), "Object 2"}])
           |> Gno.delete_data() == :ok

    refute Gno.ask!(~s(ASK { ?s <#{EX.p1()}> "Object 2" }))

    assert Gno.insert("""
           WITH <#{Gno.graph_name(:dataset)}>
           INSERT { ?s <#{EX.p3()}> ?o }
           WHERE { ?s <#{EX.p1()}> ?o }
           """) == :ok

    assert Gno.ask!("ASK { ?s <#{EX.p3()}> ?o }")

    assert Gno.clear(:all) == :ok
    refute Gno.ask!("ASK { ?s ?p ?o }")

    assert Gno.load(FOAF.__base_iri__() <> "index.rdf") == :ok
    assert Gno.ask!("ASK { <#{RDF.iri(FOAF.Agent)}> ?p ?o }")

    assert Gno.drop(:all) == :ok
    refute Gno.ask!("ASK { ?s ?p ?o }")

    assert RDF.graph([
             {EX.s1(), EX.p1(), "Test Object 1"},
             {EX.s2(), EX.p2(), "Test Object 2"},
             {EX.s3(), EX.p3(), EX.o3()}
           ])
           |> Gno.insert_data() == :ok

    assert {:ok, graph} =
             Gno.construct("""
               CONSTRUCT { ?s <#{EX.constructed()}> ?o }
               WHERE { ?s ?p ?o . FILTER(isLiteral(?o)) }
             """)

    assert RDF.Graph.triple_count(graph) == 2
    assert RDF.Graph.statements(graph) |> Enum.any?(fn {_, p, _} -> p == EX.constructed() end)

    assert {:ok, description_graph} =
             Gno.describe("""
               DESCRIBE <#{EX.s1()}>
             """)

    assert RDF.Graph.triple_count(description_graph) > 0
    assert RDF.Graph.describes?(description_graph, EX.s1())

    assert Gno.delete("""
             WITH <#{Gno.graph_name(:dataset)}>
             DELETE { <#{EX.s1()}> ?p ?o }
             WHERE { <#{EX.s1()}> ?p ?o }
           """) == :ok

    refute Gno.ask!("ASK { <#{EX.s1()}> ?p ?o }")
    assert Gno.ask!("ASK { <#{EX.s2()}> ?p ?o }")

    assert Gno.drop(:all) == :ok
    refute Gno.ask!("ASK { ?s ?p ?o }")

    assert Gno.create(Gno.graph_name(:dataset)) == :ok
  end

  test "operation helpers with named graphs" do
    graph1 = "http://example.com/graph1"
    graph2 = "http://example.com/graph2"
    graph1_opts = [graph: RDF.iri(graph1)]
    graph2_opts = [graph: RDF.iri(graph2)]

    assert Gno.insert_data(RDF.graph([{EX.s1(), EX.p1(), "Graph 1"}]), graph1_opts) == :ok
    assert Gno.insert_data(RDF.graph([{EX.s2(), EX.p1(), "Graph 2"}]), graph2_opts) == :ok

    assert Gno.insert(
             """
             INSERT DATA { GRAPH <#{graph1}> { <#{EX.s3()}> <#{EX.p1()}> "Also Graph 1" } }
             """,
             graph1_opts
           ) == :ok

    assert Gno.ask(
             """
             ASK {
               <#{EX.s1()}> <#{EX.p1()}> "Graph 1" .
               <#{EX.s3()}> <#{EX.p1()}> "Also Graph 1"
             }
             """,
             graph1_opts
           ) == {:ok, true}

    assert Gno.ask!(
             """
             ASK { <#{EX.s2()}> <#{EX.p1()}> "Graph 2" }
             """,
             graph2_opts
           )

    assert Gno.clear(RDF.iri(graph1)) == :ok
    refute Gno.ask!("ASK { ?s ?p ?o }", graph1_opts)
    assert Gno.ask!("ASK { ?s ?p ?o }", graph2_opts)

    assert Gno.load(FOAF.__base_iri__() <> "index.rdf", graph1_opts) == :ok
    assert Gno.ask!("ASK { ?s ?p ?o }", graph1_opts)

    assert Gno.drop(RDF.iri(graph2)) == :ok
    refute Gno.ask!("ASK { ?s ?p ?o }", graph2_opts)

    source_graph = "http://example.com/source"
    target_graph = "http://example.com/target"
    source_opts = [graph: RDF.iri(source_graph)]
    target_opts = [graph: RDF.iri(target_graph)]

    assert RDF.graph([{EX.s1(), EX.p1(), "Source Graph"}]) |> Gno.insert_data(source_opts) == :ok
    assert Gno.ask!("ASK { ?s ?p ?o }", source_opts)

    assert Gno.add(source_graph, target_graph) == :ok
    assert Gno.ask!("ASK { ?s ?p ?o }", target_opts)
    assert Gno.ask!("ASK { ?s ?p ?o }", source_opts)

    assert Gno.drop(RDF.iri(target_graph)) == :ok

    assert RDF.graph([{EX.s2(), EX.p2(), "Target Only"}]) |> Gno.insert_data(target_opts) == :ok
    assert Gno.copy(source_graph, target_graph) == :ok
    assert Gno.ask!("ASK { <#{EX.s1()}> ?p ?o }", target_opts)
    refute Gno.ask!("ASK { <#{EX.s2()}> ?p ?o }", target_opts)

    assert Gno.clear(RDF.iri(target_graph)) == :ok

    assert Gno.move(RDF.iri(source_graph), RDF.iri(target_graph)) == :ok
    assert Gno.ask!("ASK { ?s ?p ?o }", target_opts)
    refute Gno.ask!("ASK { ?s ?p ?o }", source_opts)

    assert Gno.copy(target_graph, graph1) == :ok
    assert Gno.drop(:all) == :ok
    refute Gno.ask!("ASK { ?s ?p ?o }", source_opts)
    refute Gno.ask!("ASK { ?s ?p ?o }", source_opts)
  end

  describe "operation helpers with :service and :store options" do
    test "raises when both :service and :store are provided" do
      service = Gno.service!()
      store = Gno.store!()

      assert_raise ArgumentError, "Cannot specify both :service and :store options", fn ->
        Gno.ask("ASK { ?s ?p ?o }", service: service, store: store)
      end
    end

    test "with :service option" do
      service = Gno.service!()

      assert RDF.graph([{EX.s1(), EX.p1(), "Default Service Data"}]) |> Gno.insert_data() == :ok
      assert Gno.ask!("ASK { <#{EX.s1()}> <#{EX.p1()}> ?o }")

      assert Gno.ask("ASK { <#{EX.s1()}> <#{EX.p1()}> ?o }", service: service) == {:ok, true}

      assert {:ok, results} =
               Gno.select("SELECT ?o WHERE { <#{EX.s1()}> <#{EX.p1()}> ?o }",
                 service: service,
                 graph: :dataset
               )

      assert length(results.results) == 1
    end

    test "with :store option" do
      store = Gno.store!()

      assert Gno.ask("ASK { ?s ?p ?o }", store: store, graph: nil) == {:ok, false}

      graph_name = "http://example.com/test-graph"
      assert Gno.ask("ASK { ?s ?p ?o }", store: store, graph: graph_name) == {:ok, false}

      assert [{EX.s1(), EX.p1(), "Store Data"}]
             |> RDF.graph()
             |> Gno.insert_data!(store: store) == :ok

      assert Gno.ask("ASK { ?s ?p ?o }", store: store, graph: nil) == {:ok, true}
      assert Gno.ask("ASK { ?s ?p ?o }", store: store) == {:ok, true}
      assert Gno.ask("ASK { ?s ?p ?o }", store: store, graph: graph_name) == {:ok, false}

      assert [{EX.s1(), EX.p1(), "Store Data"}]
             |> RDF.graph()
             |> Gno.insert_data!(store: store, graph: graph_name) == :ok

      assert Gno.ask("ASK { <#{EX.s1()}> <#{EX.p1()}> ?o }", store: store, graph: graph_name) ==
               {:ok, true}
    end

    test "inter-graph operations with :service option" do
      service = Gno.service!()

      source_data = RDF.graph([{EX.s1(), EX.p1(), "Source Data"}])
      assert Gno.insert_data(source_data, graph: :dataset) == :ok

      assert Gno.add(:dataset, :repo, service: service) == :ok

      assert Gno.ask("ASK { <#{EX.s1()}> <#{EX.p1()}> ?o }", service: service, graph: :repo) ==
               {:ok, true}

      assert Gno.clear(:all) == :ok

      assert Gno.insert_data(source_data, graph: :dataset) == :ok
      target_data = RDF.graph([{EX.s2(), EX.p2(), "Target Data"}])
      assert Gno.insert_data(target_data, graph: :repo) == :ok

      assert Gno.copy(:dataset, :repo, service: service) == :ok

      assert Gno.ask("ASK { <#{EX.s1()}> <#{EX.p1()}> ?o }", service: service, graph: :repo) ==
               {:ok, true}

      refute Gno.ask!("ASK { <#{EX.s2()}> <#{EX.p2()}> ?o }", service: service, graph: :repo)
    end

    test "inter-graph operations with alternative :service option using different repository" do
      # This test verifies that inter-graph operations use the repository from the 
      # provided :service option for graph name resolution, not the manifest's repository

      # Get the default service and repository
      default_service = Gno.service!()
      default_repo = default_service.repository

      # Create an alternative repository with different graph naming
      alt_repo = %{
        default_repo
        | __id__: RDF.iri("http://example.com/alt-repo"),
          dataset: %{default_repo.dataset | __id__: RDF.iri("http://example.com/alt-dataset")}
      }

      alt_service = %{default_service | repository: alt_repo}

      # Insert data into the alternative dataset graph directly
      source_data = RDF.graph([{EX.s1(), EX.p1(), "Alt Service Data"}])
      assert Gno.insert_data(source_data, service: alt_service, graph: :dataset) == :ok

      # Verify data is in the alternative dataset
      assert Gno.ask("ASK { <#{EX.s1()}> <#{EX.p1()}> ?o }",
               service: alt_service,
               graph: :dataset
             ) == {:ok, true}

      # Now use add operation with the alternative service
      # This should resolve :dataset to alt-dataset and :repo to alt-repo
      assert Gno.add(:dataset, :repo, service: alt_service) == :ok

      # Verify the data was copied to the alternative repo graph
      assert Gno.ask("ASK { <#{EX.s1()}> <#{EX.p1()}> ?o }",
               service: alt_service,
               graph: :repo
             ) == {:ok, true}

      expected_repo_graph = Gno.Repository.graph_name(alt_repo, :repo)

      assert Gno.ask("ASK { <#{EX.s1()}> <#{EX.p1()}> ?o }",
               store: alt_service.store,
               graph: expected_repo_graph
             ) == {:ok, true}
    end

    test "inter-graph operations with :store option require concrete graph names" do
      store = Gno.store!()

      graph1 = "http://example.com/graph1"
      graph2 = "http://example.com/graph2"

      data = RDF.graph([{EX.s1(), EX.p1(), "Test Data"}])
      operation = Gno.Store.SPARQL.Operation.insert_data!(data)
      assert Gno.execute(operation, store: store, graph: graph1) == :ok

      assert Gno.add(graph1, graph2, store: store) == :ok

      assert Gno.ask("ASK { <#{EX.s1()}> <#{EX.p1()}> ?o }", store: store, graph: graph2) ==
               {:ok, true}
    end

    test "create/drop/clear with :service as graph value" do
      test_data = RDF.graph([{EX.s1(), EX.p1(), "Service Graph Test"}])

      assert Gno.create(:service) == :ok

      assert Gno.insert_data(test_data, graph: :dataset) == :ok
      assert Gno.insert_data(test_data, graph: :repo) == :ok

      assert Gno.ask("ASK { ?s ?p ?o }", graph: :dataset) == {:ok, true}
      assert Gno.ask("ASK { ?s ?p ?o }", graph: :repo) == {:ok, true}

      assert Gno.clear(:service) == :ok

      assert Gno.ask("ASK { ?s ?p ?o }", graph: :dataset) == {:ok, false}
      assert Gno.ask("ASK { ?s ?p ?o }", graph: :repo) == {:ok, false}

      assert Gno.insert_data(test_data, graph: :dataset) == :ok
      assert Gno.insert_data(test_data, graph: :repo) == :ok

      assert Gno.drop(:service) == :ok

      assert Gno.ask("ASK { ?s ?p ?o }", graph: :dataset) == {:ok, false}
      assert Gno.ask("ASK { ?s ?p ?o }", graph: :repo) == {:ok, false}
    end
  end

  test "commit/2" do
    refute Gno.ask!("ASK { ?s ?p ?o }")

    description = EX.S1 |> EX.p1(EX.O1) |> EX.p2(EX.O2)
    expected_changeset = Gno.EffectiveChangeset.new!(add: description)

    assert {:ok, %Gno.Commit{changeset: ^expected_changeset, time: time}} =
             Gno.commit(add: description)

    assert DateTime.diff(DateTime.utc_now(), time, :second) <= 1

    assert Gno.QueryUtils.graph_query() |> Gno.execute!() |> Graph.clear_prefixes() ==
             graph(description)

    expected_changeset =
      Gno.EffectiveChangeset.new!(
        update: EX.S1 |> EX.p2("foo"),
        overwrite: EX.S1 |> EX.p2(EX.O2)
      )

    assert {:ok, %Gno.Commit{changeset: ^expected_changeset}} =
             Gno.commit(update: EX.S1 |> EX.p1(EX.O1) |> EX.p2("foo"))
             |> without_prefixes()

    assert Gno.QueryUtils.graph_query() |> Gno.execute!() |> Graph.clear_prefixes() ==
             graph(EX.S1 |> EX.p1(EX.O1) |> EX.p2("foo"))
  end

  describe "commit functions with :service option" do
    test "commit/2 with alternative :service option" do
      alt_service = alt_service(Gno.service!())
      description = EX.S1 |> EX.p1("Alt Commit Data")

      assert {:ok, %Gno.Commit{}} = Gno.commit([add: description], service: alt_service)

      assert Gno.ask("ASK { <#{RDF.iri(EX.S1)}> <#{EX.p1()}> ?o }",
               service: alt_service,
               graph: :dataset
             ) ==
               {:ok, true}

      refute Gno.ask!("ASK { <#{RDF.iri(EX.S1)}> <#{EX.p1()}> ?o }", graph: :dataset)
    end

    test "effective_changeset/2 with alternative :service option" do
      alt_service = alt_service(Gno.service!())
      initial_data = EX.S1 |> EX.p1(EX.O1)

      assert Gno.insert_data(initial_data, service: alt_service) == :ok

      changes = [add: EX.S1 |> EX.p1([EX.O1, EX.O2])]

      assert {:ok, %Gno.EffectiveChangeset{add: add_graph}} =
               Gno.effective_changeset(changes, service: alt_service)

      assert RDF.Graph.triple_count(add_graph) == 1
      assert RDF.Graph.include?(add_graph, {EX.S1, EX.p1(), EX.O2})
      refute RDF.Graph.include?(add_graph, {EX.S1, EX.p1(), EX.O1})
    end
  end
end
