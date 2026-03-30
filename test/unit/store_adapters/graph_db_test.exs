defmodule Gno.Store.Adapters.GraphDBTest do
  use GnoCase, async: true

  doctest Gno.Store.Adapters.GraphDB

  alias Gno.Store

  @configured_store_adapter configured_store_adapter()

  test "endpoint_base/1" do
    assert Store.endpoint_base(%GraphDB{dataset: "test-dataset"}) ==
             {:ok, "http://localhost:7200/repositories/test-dataset"}

    assert Store.endpoint_base(%GraphDB{dataset: "test-dataset", port: 42}) ==
             {:ok, "http://localhost:42/repositories/test-dataset"}

    assert %GraphDB{dataset: "example-dataset", scheme: "https", host: "example.com", port: nil}
           |> Store.endpoint_base() ==
             {:ok, "https://example.com/repositories/example-dataset"}
  end

  test "query_endpoint/1" do
    assert Store.query_endpoint(%GraphDB{dataset: "test-repository"}) ==
             {:ok, "http://localhost:7200/repositories/test-repository"}

    assert Store.query_endpoint(%GraphDB{dataset: "test-repository", port: 42}) ==
             {:ok, "http://localhost:42/repositories/test-repository"}

    assert Store.query_endpoint(%GraphDB{
             dataset: "example-dataset",
             scheme: "https",
             host: "example.com",
             port: nil
           }) ==
             {:ok, "https://example.com/repositories/example-dataset"}
  end

  test "update_endpoint/1" do
    assert Store.update_endpoint(%GraphDB{dataset: "test-repository"}) ==
             {:ok, "http://localhost:7200/repositories/test-repository/statements"}

    assert Store.update_endpoint(%GraphDB{dataset: "test-repository", port: 42}) ==
             {:ok, "http://localhost:42/repositories/test-repository/statements"}

    assert Store.update_endpoint(%GraphDB{
             dataset: "example-dataset",
             scheme: "https",
             host: "example.com",
             port: nil
           }) ==
             {:ok, "https://example.com/repositories/example-dataset/statements"}
  end

  test "graph_store_endpoint/1" do
    assert Store.graph_store_endpoint(%GraphDB{dataset: "test-repository"}) ==
             {:ok, "http://localhost:7200/repositories/test-repository/rdf-graphs/service"}

    assert Store.graph_store_endpoint(%GraphDB{dataset: "test-repository", port: 42}) ==
             {:ok, "http://localhost:42/repositories/test-repository/rdf-graphs/service"}

    assert Store.graph_store_endpoint(%GraphDB{
             dataset: "example-dataset",
             scheme: "https",
             host: "example.com",
             port: nil
           }) ==
             {:ok, "https://example.com/repositories/example-dataset/rdf-graphs/service"}
  end

  test "dataset_endpoint_segment/1" do
    assert Store.dataset_endpoint_segment(%GraphDB{dataset: "test-dataset"}) ==
             {:ok, "repositories/test-dataset"}

    assert Store.dataset_endpoint_segment(%GraphDB{}) ==
             {:error,
              Store.InvalidEndpointError.exception(
                "missing dataset template params [:dataset] on store #{inspect(%GraphDB{})}"
              )}
  end

  test "*_endpoint/1 functions when endpoints set directly" do
    assert Store.query_endpoint(%GraphDB{query_endpoint: EX.query_endpoint()}) ==
             {:ok, to_string(EX.query_endpoint())}

    assert Store.update_endpoint(%GraphDB{update_endpoint: EX.update_endpoint()}) ==
             {:ok, to_string(EX.update_endpoint())}

    assert %GraphDB{graph_store_endpoint: EX.graph_store_endpoint()}
           |> Store.graph_store_endpoint() ==
             {:ok, to_string(EX.graph_store_endpoint())}
  end

  describe "graph semantics" do
    test "default_graph_semantics/0" do
      assert GraphDB.default_graph_semantics() == :union
    end

    test "default_graph_iri/0" do
      assert GraphDB.default_graph_iri() == ~I<http://www.openrdf.org/schema/sesame#nil>
    end

    test "graph_semantics/1" do
      assert GraphDB.graph_semantics(%GraphDB{dataset: "test"}) == :union
    end

    test "graph_semantics/1 with manifest override to :isolated" do
      assert GraphDB.graph_semantics(%GraphDB{
               dataset: "test",
               default_graph_semantics_config: "isolated"
             }) ==
               :isolated
    end
  end

  test "rdf_star_support defaults to false" do
    assert %GraphDB{dataset: "test"}.rdf_star_support == false
  end

  describe "GraphDB REST API endpoints" do
    test "rest_base/1" do
      assert GraphDB.rest_base(%GraphDB{dataset: "test-repository"}) ==
               "http://localhost:7200/rest"

      assert GraphDB.rest_base(%GraphDB{dataset: "test-repository", port: 42}) ==
               "http://localhost:42/rest"

      assert %GraphDB{
               dataset: "example-dataset",
               scheme: "https",
               host: "example.com",
               port: nil
             }
             |> GraphDB.rest_base() ==
               "https://example.com/rest"
    end

    test "repositories_endpoint/1" do
      assert GraphDB.repositories_endpoint(%GraphDB{dataset: "test-repository"}) ==
               "http://localhost:7200/rest/repositories"
    end

    test "repository_endpoint/2" do
      assert GraphDB.repository_endpoint(%GraphDB{dataset: "test-repository"}, "my-repo") ==
               "http://localhost:7200/rest/repositories/my-repo"
    end

    test "repository_size_endpoint/2" do
      assert GraphDB.repository_size_endpoint(%GraphDB{dataset: "test-repository"}, "my-repo") ==
               "http://localhost:7200/rest/repositories/my-repo/size"
    end
  end

  if @configured_store_adapter == GraphDB do
    alias Gno.Store.SPARQL.Operation

    describe "check_availability/2" do
      test "returns error when server is not reachable" do
        assert {:error, %Gno.Store.UnavailableError{reason: :server_unreachable}} =
                 GraphDB.check_availability(unavailable_graph_db(), [])
      end
    end

    describe "check_setup/2" do
      test "returns error when server is not reachable" do
        assert {:error, %Gno.Store.UnavailableError{reason: :server_unreachable}} =
                 GraphDB.check_setup(unavailable_graph_db(), [])
      end

      test "returns error when repository does not exist" do
        store = %GraphDB{dataset: "nonexistent-repository-12345"}

        assert {:error, %Gno.Store.UnavailableError{reason: :dataset_not_found}} =
                 GraphDB.check_setup(store, [])
      end

      test "returns error when server is not reachable with check_availability: false" do
        store = %GraphDB{dataset: "nonexistent", host: "nonexistentlocalhost", port: 9999}

        assert {:error, _} = GraphDB.check_setup(store, check_availability: false)
      end
    end

    describe "Admin API functions" do
      test "all_repositories_info/1" do
        assert {:ok, _} = GraphDB.all_repositories_info(Gno.store!())
      end

      test "repository_info/1" do
        assert {:ok, _} = GraphDB.repository_info(Gno.store!())
      end

      test "repository_info/2" do
        store = Gno.store!()
        assert {:ok, _} = GraphDB.repository_info(store, store.dataset)
      end

      test "repository_info/2 with non-existent repository" do
        assert {:ok, nil} = GraphDB.repository_info(Gno.store!(), "nonexistent-repo-12345")
      end

      test "repository_size/1" do
        assert {:ok, size} = GraphDB.repository_size(Gno.store!())
        assert is_integer(size)
      end
    end

    describe "RDF-star support" do
      @rdf_star_delete """
      PREFIX ex: <http://example.com/>
      DELETE DATA { <<ex:S1 ex:p1 ex:O1>> ex:confidence "0.9"^^<http://www.w3.org/2001/XMLSchema#decimal> . }
      """
      @rdf_star_select """
      PREFIX ex: <http://example.com/>
      SELECT ?t ?o WHERE { ?t ex:confidence ?o }
      """
      @rdf_star_construct """
      PREFIX ex: <http://example.com/>
      CONSTRUCT { ?t ex:confidence ?o } WHERE { ?t ex:confidence ?o }
      """

      setup do
        store = Gno.store!()
        Operation.update!(@rdf_star_insert) |> Store.handle_sparql(store, nil)
        on_exit(fn -> Operation.update!(@rdf_star_delete) |> Store.handle_sparql(store, nil) end)
        {:ok, store: store}
      end

      test "SELECT with rdf_star_support enabled returns native triple terms", %{store: store} do
        star_store = %{store | rdf_star_support: true}

        assert {:ok, %SPARQL.Query.Result{results: [result]}} =
                 @rdf_star_select
                 |> Operation.select!()
                 |> Store.handle_sparql(star_store, nil)

        assert {~I<http://example.com/S1>, ~I<http://example.com/p1>, ~I<http://example.com/O1>} =
                 result["t"]
      end

      test "SELECT without rdf_star_support returns encoded IRI", %{store: store} do
        assert {:ok, %SPARQL.Query.Result{results: [result]}} =
                 @rdf_star_select
                 |> Operation.select!()
                 |> Store.handle_sparql(store, nil)

        assert %RDF.IRI{} = result["t"]
        assert result["t"] |> to_string() |> String.starts_with?("urn:rdf4j:triple:")
      end

      test "CONSTRUCT with rdf_star_support enabled returns native triple terms", %{store: store} do
        star_store = %{store | rdf_star_support: true}

        assert {:ok, graph} =
                 @rdf_star_construct
                 |> Operation.construct!()
                 |> Store.handle_sparql(star_store, nil)

        assert [{subject, ~I<http://example.com/confidence>, _}] = RDF.Graph.triples(graph)

        assert {~I<http://example.com/S1>, ~I<http://example.com/p1>, ~I<http://example.com/O1>} =
                 subject
      end

      test "CONSTRUCT without rdf_star_support returns encoded IRI", %{store: store} do
        assert {:ok, graph} =
                 @rdf_star_construct
                 |> Operation.construct!()
                 |> Store.handle_sparql(store, nil)

        assert [{subject, ~I<http://example.com/confidence>, _}] = RDF.Graph.triples(graph)
        assert %RDF.IRI{} = subject
        assert subject |> to_string() |> String.starts_with?("urn:rdf4j:triple:")
      end

      test "DESCRIBE with rdf_star_support enabled returns native triple terms", %{store: store} do
        star_store = %{store | rdf_star_support: true}

        assert {:ok, graph} =
                 "PREFIX ex: <http://example.com/>\nDESCRIBE <<ex:S1 ex:p1 ex:O1>>"
                 |> Operation.describe!()
                 |> Store.handle_sparql(star_store, nil)

        assert [{subject, ~I<http://example.com/confidence>, _}] = RDF.Graph.triples(graph)

        assert {~I<http://example.com/S1>, ~I<http://example.com/p1>, ~I<http://example.com/O1>} =
                 subject
      end

      test "ASK with rdf_star_support enabled works", %{store: store} do
        star_store = %{store | rdf_star_support: true}

        assert {:ok, %SPARQL.Query.Result{results: true}} =
                 "PREFIX ex: <http://example.com/>\nASK { <<ex:S1 ex:p1 ex:O1>> ex:confidence ?o }"
                 |> Operation.ask!()
                 |> Store.handle_sparql(star_store, nil)
      end
    end

    defp unavailable_graph_db do
      %GraphDB{dataset: "test", host: "nonexistentlocalhost", port: 9999}
    end
  end
end
