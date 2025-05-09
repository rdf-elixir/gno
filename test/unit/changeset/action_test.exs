defmodule Gno.Changeset.ActionTest do
  use GnoCase

  alias Gno.Changeset.Action
  import Gno.Changeset.Action

  doctest Gno.Changeset.Action

  test "extract/1" do
    assert extract(
             add: statement(1),
             remove: statement(2),
             update: statement(3),
             replace: statement(4),
             overwrite: statement(5),
             foo: "bar"
           ) ==
             {
               %{
                 add: statement(1),
                 remove: statement(2),
                 update: statement(3),
                 replace: statement(4),
                 overwrite: statement(5)
               },
               [foo: "bar"]
             }
  end

  test "empty?/1" do
    assert empty?(%{add: nil, update: nil, replace: nil, remove: nil, overwrite: nil})
    assert empty?(%{add: nil, update: nil, replace: nil, remove: nil})
    refute empty?(%{add: nil, update: nil, replace: nil, remove: nil, overwrite: statement(1)})
    refute empty?(%{add: nil, update: nil, replace: nil, remove: statement(1)})
  end

  test "sort_changes/1" do
    assert sort_changes(
             add: statement(1),
             remove: statement(2),
             update: statement(3),
             replace: statement(4),
             overwrite: statement(5)
           ) ==
             [
               overwrite: statement(5),
               remove: statement(2),
               replace: statement(4),
               update: statement(3),
               add: statement(1)
             ]
  end

  describe "graph/2" do
    test "with nil" do
      assert Action.graph(nil, :add) == nil
    end

    test "with empty list" do
      assert Action.graph([], :add) == nil
    end

    test "with RDF.Graph" do
      graph = RDF.graph([{EX.S, EX.p(), EX.O}])
      assert Action.graph(graph, :add) == graph
    end

    test "with RDF.Description" do
      description = EX.S |> EX.p(EX.O)
      assert Action.graph(description, :add) == RDF.graph(description)
    end

    test "with tuple (triple)" do
      triple = {EX.S, EX.p(), EX.O}
      assert Action.graph(triple, :add) == RDF.graph(triple)
    end

    test "with list of triples" do
      triples = [
        {EX.S1, EX.p1(), EX.O1},
        {EX.S2, EX.p2(), EX.O2}
      ]

      assert Action.graph(triples, :add) == RDF.graph(triples)
    end

    test "with mixed list of different forms" do
      assert [
               {EX.S1, EX.p1(), EX.O1},
               EX.S2 |> EX.p2(EX.O2),
               RDF.graph([{EX.S3, EX.p3(), EX.O3}]),
               [{EX.S4, EX.p4(), EX.O4}]
             ]
             |> Action.graph(:add) ==
               RDF.graph([
                 {EX.S1, EX.p1(), EX.O1},
                 {EX.S2, EX.p2(), EX.O2},
                 {EX.S3, EX.p3(), EX.O3},
                 {EX.S4, EX.p4(), EX.O4}
               ])
    end

    test "with invalid atom" do
      assert_raise Protocol.UndefinedError, fn ->
        Action.graph(:foo, :add)
      end
    end
  end
end
