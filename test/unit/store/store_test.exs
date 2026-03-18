defmodule Gno.StoreTest do
  use Gno.StoreCase

  doctest Gno.Store.GenSPARQL

  alias Gno.Store.InvalidEndpointError
  alias Gno.Store.SPARQL.Operation

  @configured_store_adapter configured_store_adapter()

  # These tests serve as integration tests for
  # - Gno.Store
  # - Gno.Store.GenSPARQL
  # - all Gno.Store.Adapter.handle_sparql/4 implementations
  #   (since this test suite is supposed to be run on the different triple stores in its entirety)

  describe "handle/4" do
    test "default graph" do
      assert {:ok, %SPARQL.Query.Result{results: []}} =
               "SELECT * WHERE { ?s ?p ?o . }"
               |> Operation.select!()
               |> Store.handle_sparql(Manifest.store!(), nil)

      assert EX.S
             |> EX.p(EX.O)
             |> RDF.graph()
             |> Operation.insert_data!()
             |> Store.handle_sparql(Manifest.store!(), nil) ==
               :ok

      assert {:ok,
              %SPARQL.Query.Result{
                results: [
                  %{
                    "s" => ~I<http://example.com/S>,
                    "p" => ~I<http://example.com/p>,
                    "o" => ~I<http://example.com/O>
                  }
                ]
              }} =
               "SELECT * WHERE { ?s ?p ?o . }"
               |> Operation.select!()
               |> Store.handle_sparql(Manifest.store!(), nil)
    end

    test "named graph" do
      assert {:ok, %SPARQL.Query.Result{results: []}} =
               "SELECT * WHERE { ?s ?p ?o . }"
               |> Operation.select!()
               |> Store.handle_sparql(Manifest.store!(), Manifest.dataset!().__id__)

      assert EX.S
             |> EX.p(EX.O)
             |> RDF.graph()
             |> Operation.insert_data!()
             |> Store.handle_sparql(Manifest.store!(), Manifest.dataset!().__id__) ==
               :ok

      assert {:ok,
              %SPARQL.Query.Result{
                results: [
                  %{
                    "s" => ~I<http://example.com/S>,
                    "p" => ~I<http://example.com/p>,
                    "o" => ~I<http://example.com/O>
                  }
                ]
              }} =
               "SELECT * WHERE { ?s ?p ?o . }"
               |> Operation.select!()
               |> Store.handle_sparql(Manifest.store!(), Manifest.dataset!().__id__)

      graph =
        EX.S2
        |> EX.p(EX.O2)
        |> RDF.graph()

      assert graph
             |> Operation.insert_data!()
             |> Store.handle_sparql(Manifest.store!(), Manifest.repository!().__id__) ==
               :ok

      assert {:ok, result} =
               "CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o . }"
               |> Operation.construct!()
               |> Store.handle_sparql(Manifest.store!(), Manifest.repository!().__id__)

      # some triple stores (like Fuseki) add all known prefixes
      assert Graph.clear_prefixes(result) == graph
    end
  end

  test "endpoint_base/1" do
    assert Store.endpoint_base(%Store{}) ==
             {:error,
              InvalidEndpointError.exception(
                "endpoint_base not supported on generic #{inspect(%Store{})}"
              )}

    store = %Store{query_endpoint: EX.query_endpoint()}

    assert Store.endpoint_base(store) ==
             {:error,
              InvalidEndpointError.exception(
                "endpoint_base not supported on generic #{inspect(store)}"
              )}
  end

  test "query_endpoint/1" do
    assert Store.query_endpoint(%Store{}) ==
             {:error,
              InvalidEndpointError.exception(
                "undefined query_endpoint on generic #{inspect(%Store{})}"
              )}

    store = %Store{scheme: "https", host: "example.com", port: nil}

    assert Store.query_endpoint(store) ==
             {:error,
              InvalidEndpointError.exception(
                "undefined query_endpoint on generic #{inspect(store)}"
              )}
  end

  test "update_endpoint/1" do
    assert Store.update_endpoint(%Store{}) ==
             {:error,
              InvalidEndpointError.exception(
                "undefined update_endpoint on generic #{inspect(%Store{})}"
              )}

    store = %Store{scheme: "https", host: "example.com", port: nil}

    assert Store.update_endpoint(store) ==
             {:error,
              InvalidEndpointError.exception(
                "undefined update_endpoint on generic #{inspect(store)}"
              )}
  end

  test "graph_store_endpoint/1" do
    assert Store.graph_store_endpoint(%Store{}) ==
             {:error,
              InvalidEndpointError.exception(
                "undefined graph_store_endpoint on generic #{inspect(%Store{})}"
              )}

    store = %Store{scheme: "https", host: "example.com", port: nil}

    assert Store.graph_store_endpoint(store) ==
             {:error,
              InvalidEndpointError.exception(
                "undefined graph_store_endpoint on generic #{inspect(store)}"
              )}
  end

  test "dataset_endpoint_segment/1" do
    store = %Store{query_endpoint: EX.query_endpoint()}

    assert Store.dataset_endpoint_segment(store) ==
             {:error,
              InvalidEndpointError.exception(
                "dataset_endpoint_segment not supported on generic #{inspect(store)}"
              )}
  end

  test "graph_semantics/1 on generic store" do
    assert Store.graph_semantics(%Store{}) == :isolated
  end

  test "graph_semantics/1 on generic store with manifest override" do
    assert Store.graph_semantics(%Store{default_graph_semantics_config: "union"}) == :union
    assert Store.graph_semantics(%Store{default_graph_semantics_config: "isolated"}) == :isolated
    assert Store.graph_semantics(%Store{default_graph_semantics_config: nil}) == :isolated
  end

  test "default_graph_iri/1 on generic store" do
    assert Store.default_graph_iri(%Store{}) == nil
  end

  test "*_endpoint/1 functions when endpoints set directly" do
    assert %Store{query_endpoint: EX.query_endpoint()} |> Store.query_endpoint() ==
             {:ok, to_string(EX.query_endpoint())}

    assert %Store{update_endpoint: EX.update_endpoint()} |> Store.update_endpoint() ==
             {:ok, to_string(EX.update_endpoint())}

    assert %Store{graph_store_endpoint: EX.graph_store_endpoint()}
           |> Store.graph_store_endpoint() ==
             {:ok, to_string(EX.graph_store_endpoint())}
  end

  describe "check_availability/2" do
    test "returns :ok when store is reachable" do
      assert :ok = Store.check_availability(Manifest.store!())
    end

    test "returns error when store is not reachable" do
      store = %{Manifest.store!() | host: "nonexistent.localhost", port: 99999}

      expected_reason =
        case @configured_store_adapter do
          Fuseki -> :server_unreachable
          _ -> :query_failed
        end

      assert {:error, %Gno.Store.UnavailableError{reason: ^expected_reason}} =
               Store.check_availability(store)
    end
  end

  describe "check_setup/2" do
    test "returns :ok when dataset exists and is functional" do
      store = Manifest.store!()
      assert :ok = Store.check_setup(store, [])
    end

    test "returns error when store is not reachable" do
      store = %{Manifest.store!() | host: "nonexistent.localhost", port: 99999}

      expected_reason =
        case @configured_store_adapter do
          Fuseki -> :server_unreachable
          _ -> :query_failed
        end

      assert {:error, %Gno.Store.UnavailableError{reason: ^expected_reason}} =
               Store.check_setup(store, [])
    end

    if @configured_store_adapter in [Fuseki] do
      test "returns error when store is not reachable with check_availability: false" do
        store = %{Manifest.store!() | host: "nonexistentlocalhost", port: 99999}

        assert {:error, _} = Store.check_setup(store, check_availability: false)
      end
    end
  end
end
