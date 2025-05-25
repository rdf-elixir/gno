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
end
