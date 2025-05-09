defmodule Gno.Changeset.ValidationTest do
  use GnoCase

  alias Gno.Changeset.Validation
  alias Gno.InvalidChangesetError

  doctest Gno.Changeset.Validation

  test "valid changeset" do
    assert Validation.validate(changeset()) == {:ok, changeset()}
  end

  test "empty changeset" do
    assert Validation.validate(Changeset.empty()) ==
             {:error, InvalidChangesetError.exception(reason: :empty)}

    assert Validation.validate(Changeset.empty(), allow_empty: true) ==
             {:ok, Changeset.empty()}
  end

  test "overlapping add and remove statements" do
    shared_statements = graph([1])

    assert %Changeset{
             add: graph() |> Graph.add(shared_statements),
             remove: shared_statements
           }
           |> Validation.validate() ==
             {:error,
              InvalidChangesetError.exception(
                reason:
                  "the following statements are in both add and remove: #{inspect(Graph.triples(shared_statements))}"
              )}

    assert %Changeset{
             update: graph() |> Graph.add(shared_statements),
             remove: shared_statements
           }
           |> Validation.validate() ==
             {:error,
              InvalidChangesetError.exception(
                reason:
                  "the following statements are in both add and remove: #{inspect(Graph.triples(shared_statements))}"
              )}

    assert %Changeset{
             replace: graph() |> Graph.add(shared_statements),
             remove: shared_statements
           }
           |> Validation.validate() ==
             {:error,
              InvalidChangesetError.exception(
                reason:
                  "the following statements are in both add and remove: #{inspect(Graph.triples(shared_statements))}"
              )}
  end

  test "overlapping add statements" do
    shared_statements = graph([1])

    assert %Changeset{
             add: graph() |> Graph.add(shared_statements),
             update: shared_statements
           }
           |> Validation.validate() ==
             {:error,
              InvalidChangesetError.exception(
                reason:
                  "the following statements are in multiple adds: #{inspect(Graph.triples(shared_statements))}"
              )}

    assert %Changeset{
             add: shared_statements,
             replace: graph() |> Graph.add(shared_statements)
           }
           |> Validation.validate() ==
             {:error,
              InvalidChangesetError.exception(
                reason:
                  "the following statements are in multiple adds: #{inspect(Graph.triples(shared_statements))}"
              )}

    assert %Changeset{
             update: graph() |> Graph.add(shared_statements),
             replace: shared_statements
           }
           |> Validation.validate() ==
             {:error,
              InvalidChangesetError.exception(
                reason:
                  "the following statements are in multiple adds: #{inspect(Graph.triples(shared_statements))}"
              )}
  end

  test "overlapping add patterns" do
    add1 = {EX.s(), EX.p(), EX.o1()}
    add2 = {EX.s(), EX.p(), EX.o2()}

    assert %Changeset{
             replace: graph() |> Graph.add(add1),
             update: RDF.graph([add2])
           }
           |> Validation.validate() ==
             {:error,
              InvalidChangesetError.exception(
                reason:
                  "the following update statements overlap with replace overwrites: #{inspect([add2])}"
              )}

    assert %Changeset{
             add: graph() |> Graph.add(add1),
             replace: RDF.graph([add2])
           }
           |> Validation.validate() ==
             {:error,
              InvalidChangesetError.exception(
                reason:
                  "the following add statements overlap with replace overwrites: #{inspect([add1])}"
              )}

    assert %Changeset{
             add: graph() |> Graph.add(add1),
             update: RDF.graph([add2])
           }
           |> Validation.validate() ==
             {:error,
              InvalidChangesetError.exception(
                reason:
                  "the following add statements overlap with update overwrites: #{inspect([add1])}"
              )}

    assert %Changeset{
             update: graph() |> Graph.add(add1),
             add: RDF.graph([add2])
           }
           |> Validation.validate() ==
             {:error,
              InvalidChangesetError.exception(
                reason:
                  "the following add statements overlap with update overwrites: #{inspect([add2])}"
              )}

    assert {:ok, _} =
             %Changeset{
               add: graph() |> Graph.add(add1),
               update: RDF.graph({EX.s(), EX.p2(), EX.o2()})
             }
             |> Validation.validate()

    assert {:ok, _} =
             %Changeset{
               update: graph() |> Graph.add(add1),
               add: RDF.graph({EX.s(), EX.p2(), EX.o2()})
             }
             |> Validation.validate()
  end
end
