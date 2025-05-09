defmodule Gno.Changeset.FormatterTest do
  use GnoCase

  doctest Gno.Changeset.Formatter

  alias Gno.Changeset.Formatter
  alias Gno.EffectiveChangeset

  import Gno.Utils

  describe "short_stat" do
    test "changeset" do
      assert Formatter.format(changeset(), :short_stat) ==
               " 3 resources changed, 3 insertions(+), 1 deletions(-)"

      assert Formatter.format(effective_changeset(), :short_stat) ==
               " 3 resources changed, 3 insertions(+), 1 deletions(-)"
    end
  end

  describe "resource_only" do
    test "changeset" do
      assert Formatter.format(effective_changeset(), :resource_only) ==
               """
               http://example.com/Foo
               http://example.com/S1
               http://example.com/S2
               """
               |> String.trim_trailing()

      assert Formatter.format(changeset(), :resource_only) ==
               """
               http://example.com/Foo
               http://example.com/S1
               http://example.com/S2
               """
               |> String.trim_trailing()
    end
  end

  describe "stat" do
    test "changeset" do
      assert Formatter.format(effective_changeset(), :stat, color: false) ==
               """
                http://example.com/Foo | 1 -
                http://example.com/S1  | 1 +
                http://example.com/S2  | 2 ++
                3 resources changed, 3 insertions(+), 1 deletions(-)
               """
               |> String.trim_trailing()

      assert Formatter.format(changeset(), :stat, color: false) ==
               """
                http://example.com/Foo | 1 -
                http://example.com/S1  | 1 +
                http://example.com/S2  | 2 ++
                3 resources changed, 3 insertions(+), 1 deletions(-)
               """
               |> String.trim_trailing()
    end

    test "lines are never wrapped" do
      large_commit =
        effective_changeset(
          add: 1..3 |> Enum.to_list() |> graph(),
          update: 1..100 |> Enum.map(&{10, &1}) |> graph()
        )

      assert_no_line_wrap(Formatter.format(large_commit, :stat, color: false))

      large_resource =
        changeset(
          add:
            graph([
              {"http://example.com/#{String.duplicate("very", terminal_width())}long", EX.P, EX.O}
            ]),
          remove: 1..100 |> Enum.map(&{10, &1}) |> graph()
        )

      assert_no_line_wrap(Formatter.format(large_resource, :stat, color: false))
    end
  end

  describe "changes" do
    test "changeset" do
      assert changeset(
               add: statement(1),
               update: statements([2, {1, 2}]),
               replace: statement(3),
               remove: statement(4)
             )
             |> Formatter.format(:changes) ==
               """
               \e[0m  <http://example.com/s1>
               \e[32m+     <http://example.com/p1> <http://example.com/o1> ;
               \e[36m±     <http://example.com/p2> <http://example.com/o2> .

               \e[0m  <http://example.com/s2>
               \e[36m±     <http://example.com/p2> <http://example.com/o2> .

               \e[0m  <http://example.com/s3>
               \e[96m⨦     <http://example.com/p3> <http://example.com/o3> .

               \e[0m  <http://example.com/s4>
               \e[31m-     <http://example.com/p4> <http://example.com/o4> .
               \e[0m
               """
               |> String.trim_trailing()

      assert EffectiveChangeset.new!(
               add: graph([1]),
               update: graph([2, {1, 2}], prefixes: [ex: EX]),
               overwrite: graph([{2, 1}])
             )
             |> Formatter.format(:changes, color: false) ==
               """
               @prefix ex: <http://example.com/> .

                 ex:s1
               +     ex:p1 ex:o1 ;
               ±     ex:p2 ex:o2 .

                 ex:s2
               ~     ex:p1 ex:o1 ;
               ±     ex:p2 ex:o2 .
               """
    end

    test ":context_data opt" do
      assert EffectiveChangeset.new!(
               add: graph([1]),
               update: graph([2, {1, 2}], prefixes: [ex: EX]),
               overwrite: graph([{2, 1}])
             )
             |> Formatter.format(:changes,
               context_data: [
                 statement({1, 3}),
                 statement(3)
               ]
             ) ==
               """
               @prefix ex: <http://example.com/> .

               \e[0m  ex:s1
               \e[32m+     ex:p1 ex:o1 ;
               \e[36m±     ex:p2 ex:o2 ;
               \e[0m      ex:p3 ex:o3 .

               \e[0m  ex:s2
               \e[91m~     ex:p1 ex:o1 ;
               \e[36m±     ex:p2 ex:o2 .

               \e[0m  ex:s3
               \e[0m      ex:p3 ex:o3 .
               \e[0m
               """
               |> String.trim_trailing()
    end
  end

  def assert_no_line_wrap(text) do
    text
    |> String.split("\n")
    |> Enum.each(fn line ->
      assert String.length(line) <= terminal_width()
    end)
  end
end
