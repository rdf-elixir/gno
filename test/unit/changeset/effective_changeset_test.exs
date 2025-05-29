defmodule Gno.EffectiveChangesetTest do
  use GnoCase

  doctest Gno.EffectiveChangeset

  alias Gno.EffectiveChangeset
  alias Gno.InvalidChangesetError

  @statement_forms [
    {EX.S, EX.p(), EX.O},
    [{EX.S1, EX.p1(), EX.O1}, {EX.S2, EX.p2(), EX.O2}],
    EX.S |> EX.p(EX.O),
    graph()
  ]

  describe "new/1" do
    test "with a keyword list" do
      assert EffectiveChangeset.new(
               add: statement(1),
               update: statement(2),
               replace: statement(3),
               remove: statement(4),
               overwrite: statement(5)
             ) ==
               {:ok,
                %EffectiveChangeset{
                  add: graph([1]),
                  update: graph([2]),
                  replace: graph([3]),
                  remove: graph([4]),
                  overwrite: graph([5])
                }}
    end

    test "with an action map" do
      assert EffectiveChangeset.new(%{add: graph([1]), remove: statement(2)}) ==
               {:ok,
                %EffectiveChangeset{
                  add: graph([1]),
                  remove: graph([2])
                }}
    end

    test "with a changeset" do
      assert EffectiveChangeset.new(effective_changeset()) == {:ok, effective_changeset()}
    end

    test "statements in various forms" do
      Enum.each(@statement_forms, fn statements ->
        assert EffectiveChangeset.new(add: statements) ==
                 {:ok, %EffectiveChangeset{add: RDF.graph(statements)}}

        assert EffectiveChangeset.new(remove: statements) ==
                 {:ok, %EffectiveChangeset{remove: RDF.graph(statements)}}

        assert EffectiveChangeset.new(update: statements) ==
                 {:ok, %EffectiveChangeset{update: RDF.graph(statements)}}

        assert EffectiveChangeset.new(replace: statements) ==
                 {:ok, %EffectiveChangeset{replace: RDF.graph(statements)}}
      end)
    end

    test "without statements" do
      assert EffectiveChangeset.new(add: nil) ==
               {:error, InvalidChangesetError.exception(reason: :empty)}

      assert EffectiveChangeset.new(remove: nil) ==
               {:error, InvalidChangesetError.exception(reason: :empty)}

      assert EffectiveChangeset.new(update: nil) ==
               {:error, InvalidChangesetError.exception(reason: :empty)}

      assert EffectiveChangeset.new(replace: nil) ==
               {:error, InvalidChangesetError.exception(reason: :empty)}
    end

    test "validates the changeset" do
      assert {:error, %InvalidChangesetError{}} =
               EffectiveChangeset.new(add: statement(1), remove: statement(1))
    end
  end

  describe "extract/1" do
    test "with direct action keys" do
      assert EffectiveChangeset.extract(add: graph([1]), remove: statement(2), foo: :bar) ==
               {:ok,
                %EffectiveChangeset{
                  add: graph([1]),
                  remove: graph([2])
                }, [foo: :bar]}
    end

    test "with a :changeset value and no direct action keys" do
      assert EffectiveChangeset.extract(
               changeset: [add: graph([1]), remove: statement(2)],
               foo: :bar
             ) ==
               {:ok,
                %EffectiveChangeset{
                  add: graph([1]),
                  remove: graph([2])
                }, [foo: :bar]}
    end

    test "with a :changeset value and direct action keys" do
      assert EffectiveChangeset.extract(
               changeset: [add: graph([1])],
               remove: statement(2),
               foo: :bar
             ) ==
               {
                 :error,
                 InvalidChangesetError.exception(
                   reason: ":changeset can not be used along additional changes"
                 )
               }
    end
  end

  describe "merge/2" do
    test "single add" do
      assert [
               add: statement(1),
               # an add overlapping with an update never happens effectively
               update: nil,
               # an add overlapping with a replace never happens effectively
               replace: nil,
               remove: statements([2, 4]),
               overwrite: statement(3)
             ]
             |> EffectiveChangeset.merge(add: statements([2, 3, 5])) ==
               EffectiveChangeset.new!(
                 add: graph([1, 5]),
                 remove: graph([4]),
                 overwrite: nil
               )
    end

    test "single update" do
      assert [
               # an update overlapping with an add never happens effectively
               add: nil,
               update: statement(1),
               # an update overlapping with a replace never happens effectively
               replace: nil,
               remove: statements([2, 4]),
               overwrite: statement(3)
             ]
             |> EffectiveChangeset.merge(update: statements([2, 3, 5])) ==
               EffectiveChangeset.new!(
                 update: graph([1, 5]),
                 remove: graph([4]),
                 overwrite: nil
               )
    end

    test "single replace" do
      assert [
               # a replace overlapping with an add never happens effectively
               add: nil,
               # a replace overlapping with an update never happens effectively
               update: nil,
               replace: statement(1),
               remove: statements([2, 4]),
               overwrite: statement(3)
             ]
             |> EffectiveChangeset.merge(replace: statements([2, 3, 5])) ==
               EffectiveChangeset.new!(
                 replace: graph([1, 5]),
                 remove: graph([4]),
                 overwrite: nil
               )
    end

    test "single remove" do
      assert [
               add: statements([1, 5]),
               update: statement(2),
               replace: statement(3),
               remove: statement(4),
               # a remove overlapping with an overwrite never happens effectively
               overwrite: nil
             ]
             |> EffectiveChangeset.merge(remove: statements([1, 2, 3, 6])) ==
               EffectiveChangeset.new!(
                 add: graph([5]),
                 update: nil,
                 replace: nil,
                 remove: graph([4, 6])
               )
    end

    test "single overwrite" do
      assert [
               add: statement(1),
               update: statements([2, 5]),
               replace: statements([3, 6]),
               # a remove overlapping with an overwrite never happens effectively
               remove: nil,
               overwrite: nil
             ]
             |> EffectiveChangeset.merge(overwrite: statements([1, 2, 3])) ==
               EffectiveChangeset.new!(
                 add: nil,
                 update: graph([5]),
                 replace: graph([6]),
                 overwrite: nil
               )
    end

    test "disjunctive changesets" do
      assert [
               add: statement(:S1_1),
               update: statement(:S2_1),
               replace: statement(:S3_1),
               remove: statement(:S4_1),
               overwrite: statement(:S5_1)
             ]
             |> EffectiveChangeset.merge(
               add: statement(:S1_2),
               update: statement(:S2_2),
               replace: statement(:S3_2),
               remove: statement(:S4_2),
               overwrite: statement(:S5_2)
             ) ==
               EffectiveChangeset.new!(
                 add: graph([:S1_1, :S1_2]),
                 update: graph([:S2_1, :S2_2]),
                 replace: graph([:S3_1, :S3_2]),
                 remove: graph([:S4_1, :S4_2]),
                 overwrite: graph([:S5_1, :S5_2])
               )
    end

    test "equal changesets" do
      changeset =
        [
          add: graph([1]),
          update: graph([2]),
          replace: graph([3]),
          remove: graph([4]),
          overwrite: graph([5])
        ]

      assert EffectiveChangeset.merge(changeset, changeset) ==
               EffectiveChangeset.new!(changeset)
    end

    test "empty results" do
      assert [add: statement(1)]
             |> EffectiveChangeset.merge(remove: statement(1)) ==
               EffectiveChangeset.empty()

      assert [remove: statement(1)]
             |> EffectiveChangeset.merge(add: statement(1)) ==
               EffectiveChangeset.empty()
    end
  end

  describe "merge/1" do
    test "one element list" do
      assert EffectiveChangeset.merge([Changeset.new!(add: statement(1))]) ==
               EffectiveChangeset.new!(add: statement(1))
    end

    test "two element list" do
      assert EffectiveChangeset.merge([
               [add: statement(1)],
               [remove: statement(2)]
             ]) ==
               [add: statement(1)]
               |> EffectiveChangeset.merge(remove: statement(2))
    end

    test "three element list" do
      assert EffectiveChangeset.merge([
               [add: statement(1)],
               [remove: statement(1)],
               [add: statement(1)]
             ]) ==
               EffectiveChangeset.new!(add: statement(1))
    end

    test "four element list" do
      assert EffectiveChangeset.merge([
               [add: EX.S1 |> EX.p1(EX.O1)],
               [remove: EX.S1 |> EX.p1(EX.O1)],
               [add: EX.S1 |> EX.p4(EX.O4)],
               [replace: EX.S1 |> EX.p2(EX.O2), overwrite: EX.S1 |> EX.p4(EX.O4)]
             ]) ==
               EffectiveChangeset.new!(replace: EX.S1 |> EX.p2(EX.O2))
    end
  end

  test "invert/1" do
    assert EffectiveChangeset.new!(
             add: statement(1),
             update: statement(2),
             replace: statement(3),
             remove: statement(4),
             overwrite: statement(5)
           )
           |> EffectiveChangeset.invert() ==
             %EffectiveChangeset{
               add: graph([4, 5]),
               remove: graph([1, 2, 3])
             }

    assert EffectiveChangeset.new!(
             replace: statement(1),
             overwrite: statement(2)
           )
           |> EffectiveChangeset.invert() ==
             %EffectiveChangeset{
               add: graph([2]),
               remove: graph([1])
             }

    assert EffectiveChangeset.empty() |> EffectiveChangeset.invert() ==
             EffectiveChangeset.empty()
  end

  test "limit/3" do
    changeset = %EffectiveChangeset{
      add: graph([1, {EX.S, EX.p1(), EX.O1}]),
      update: nil,
      replace: graph([1]),
      remove: graph([2, {EX.S, EX.p1(), EX.O2}]),
      overwrite: graph([{EX.S, EX.p2(), EX.O2}])
    }

    assert EffectiveChangeset.limit(changeset, :resource, RDF.iri(EX.S)) ==
             %EffectiveChangeset{
               add: graph([{EX.S, EX.p1(), EX.O1}]),
               remove: graph([{EX.S, EX.p1(), EX.O2}]),
               overwrite: graph([{EX.S, EX.p2(), EX.O2}])
             }
  end

  test "to_rdf/1" do
    assert EffectiveChangeset.new!(
             add: statement(1),
             update: statement(2),
             replace: statement(3),
             remove: statement(4),
             overwrite: statement(5)
           )
           |> EffectiveChangeset.to_rdf() ==
             RDF.Dataset.new()
             |> RDF.Dataset.add(statement(1), graph: Gno.Addition)
             |> RDF.Dataset.add(statement(2), graph: Gno.Update)
             |> RDF.Dataset.add(statement(3), graph: Gno.Replacement)
             |> RDF.Dataset.add(statement(4), graph: Gno.Removal)
             |> RDF.Dataset.add(statement(5), graph: Gno.Overwrite)
             |> RDF.Dataset.add(Graph.new(prefixes: [gno: Gno]))

    assert EffectiveChangeset.new!(add: statement(1))
           |> EffectiveChangeset.to_rdf() ==
             RDF.Dataset.new()
             |> RDF.Dataset.add(statement(1), graph: Gno.Addition)
             |> RDF.Dataset.add(Graph.new(prefixes: [gno: Gno]))
  end

  test "to_rdf/2" do
    assert EffectiveChangeset.new!(add: statement(1))
           |> EffectiveChangeset.to_rdf(prefixes: [ex: EX]) ==
             RDF.Dataset.new()
             |> RDF.Dataset.add(statement(1), graph: Gno.Addition)
             |> RDF.Dataset.add(Graph.new(prefixes: [gno: Gno, ex: EX]))
  end

  test "from_rdf/1" do
    assert RDF.Dataset.new()
           |> RDF.Dataset.add(statement(1), graph: Gno.Addition)
           |> RDF.Dataset.add(statement(2), graph: Gno.Update)
           |> RDF.Dataset.add(statement(3), graph: Gno.Replacement)
           |> RDF.Dataset.add(statement(4), graph: Gno.Removal)
           |> RDF.Dataset.add(statement(5), graph: Gno.Overwrite)
           |> EffectiveChangeset.from_rdf() ==
             EffectiveChangeset.new!(
               add: statement(1),
               update: statement(2),
               replace: statement(3),
               remove: statement(4),
               overwrite: statement(5)
             )

    assert RDF.Dataset.new()
           |> RDF.Dataset.add(statement(1), graph: Gno.Addition)
           |> EffectiveChangeset.from_rdf() ==
             EffectiveChangeset.new!(add: statement(1))
  end
end
