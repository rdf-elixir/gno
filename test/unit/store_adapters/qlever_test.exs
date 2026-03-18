defmodule Gno.Store.Adapters.QleverTest do
  use GnoCase, async: true

  doctest Gno.Store.Adapters.Qlever

  alias Gno.Store.Adapters.Qlever
  alias Gno.Store

  test "endpoint_base/1" do
    assert Store.endpoint_base(%Qlever{}) ==
             {:ok, "http://localhost:7001"}

    assert Store.endpoint_base(%Qlever{port: 7019}) ==
             {:ok, "http://localhost:7019"}

    assert Store.endpoint_base(%Qlever{scheme: "https", host: "example.com", port: nil}) ==
             {:ok, "https://example.com"}
  end

  test "query_endpoint/1" do
    assert Store.query_endpoint(%Qlever{}) ==
             {:ok, "http://localhost:7001"}

    assert Store.query_endpoint(%Qlever{port: 7019}) ==
             {:ok, "http://localhost:7019"}

    assert Store.query_endpoint(%Qlever{scheme: "https", host: "example.com", port: nil}) ==
             {:ok, "https://example.com"}
  end

  test "update_endpoint/1" do
    assert Store.update_endpoint(%Qlever{}) ==
             {:ok, "http://localhost:7001"}

    assert Store.update_endpoint(%Qlever{port: 7019}) ==
             {:ok, "http://localhost:7019"}

    assert Store.update_endpoint(%Qlever{scheme: "https", host: "example.com", port: nil}) ==
             {:ok, "https://example.com"}
  end

  test "graph_store_endpoint/1" do
    assert Store.graph_store_endpoint(%Qlever{}) ==
             {:ok, "http://localhost:7001"}

    assert Store.graph_store_endpoint(%Qlever{port: 7019}) ==
             {:ok, "http://localhost:7019"}

    assert Store.graph_store_endpoint(%Qlever{scheme: "https", host: "example.com", port: nil}) ==
             {:ok, "https://example.com"}
  end

  test "dataset_endpoint_segment/1" do
    assert Store.dataset_endpoint_segment(%Qlever{}) == {:ok, ""}
  end

  test "*_endpoint/1 functions when endpoints set directly" do
    assert Store.query_endpoint(%Qlever{query_endpoint: EX.query_endpoint()}) ==
             {:ok, to_string(EX.query_endpoint())}

    assert Store.update_endpoint(%Qlever{update_endpoint: EX.update_endpoint()}) ==
             {:ok, to_string(EX.update_endpoint())}

    assert Store.graph_store_endpoint(%Qlever{graph_store_endpoint: EX.graph_store_endpoint()}) ==
             {:ok, to_string(EX.graph_store_endpoint())}
  end

  describe "graph semantics" do
    test "default_graph_semantics/0" do
      assert Qlever.default_graph_semantics() == :union
    end

    test "default_graph_iri/0" do
      assert Qlever.default_graph_iri() ==
               ~I<http://qlever.cs.uni-freiburg.de/builtin-functions/default-graph>
    end

    test "graph_semantics/1" do
      assert Qlever.graph_semantics(%Qlever{}) == :union
    end

    test "graph_semantics/1 with manifest override to :isolated" do
      assert Qlever.graph_semantics(%Qlever{default_graph_semantics_config: "isolated"}) ==
               :isolated
    end

    test "Store.graph_semantics/1 dispatch" do
      assert Store.graph_semantics(%Qlever{}) == :union
    end

    test "Store.default_graph_iri/1 dispatch" do
      assert Store.default_graph_iri(%Qlever{}) ==
               ~I<http://qlever.cs.uni-freiburg.de/builtin-functions/default-graph>
    end
  end

  describe "unsupported operations" do
    for op <- [:load, :clear, :create, :add, :copy, :move] do
      test "#{op} returns UnsupportedOperationError" do
        adapter = %Qlever{}

        operation =
          case unquote(op) do
            :load -> Gno.Store.SPARQL.Operation.load!(RDF.iri("http://example.com/data"))
            :clear -> Gno.Store.SPARQL.Operation.clear!()
            :create -> Gno.Store.SPARQL.Operation.create!()
            :add -> Gno.Store.SPARQL.Operation.add!(:default, EX.Target)
            :copy -> Gno.Store.SPARQL.Operation.copy!(:default, EX.Target)
            :move -> Gno.Store.SPARQL.Operation.move!(:default, EX.Target)
          end

        assert {:error,
                %Gno.Store.UnsupportedOperationError{operation: unquote(op), store: ^adapter}} =
                 Qlever.handle_sparql(operation, adapter, nil)
      end
    end
  end
end
