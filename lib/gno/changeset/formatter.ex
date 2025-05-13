defmodule Gno.Changeset.Formatter do
  @moduledoc false

  alias Gno.Changeset
  alias RDF.{Graph, Description, Turtle}
  alias IO.ANSI

  import Gno.Utils

  # ATTENTION: The order of this list is relevant! Since Optimus, the command-line
  # parser used in the CLI, unfortunately doesn't keep the order of the options,
  # we show multiple selected format in the order defined by this list.
  @formats ~w[changes stat resource_only short_stat]a
  def formats, do: @formats

  def format(changeset, format, opts \\ []) do
    changeset
    |> do_format(format, opts)
    |> IO.iodata_to_binary()
  end

  defp do_format({insertions, deletions, overwrites, changed_resources}, :short_stat, _opts) do
    insertions_count = Graph.triple_count(insertions)
    deletions_count = Graph.triple_count(deletions)
    overwrites_count = Graph.triple_count(overwrites)

    [
      " #{Enum.count(changed_resources)} resources changed",
      if(insertions_count > 0, do: "#{insertions_count} insertions(+)"),
      if(deletions_count > 0, do: "#{deletions_count} deletions(-)"),
      if(overwrites_count > 0, do: "#{overwrites_count} overwrites(~)")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.intersperse(", ")
  end

  defp do_format(changeset, :short_stat, opts) do
    insertions = Changeset.Helper.inserts(changeset)
    deletions = Changeset.Helper.removals(changeset)
    overwrites = Changeset.Helper.overwrites(changeset)
    changed_resources = changed_resources({insertions, deletions, overwrites})

    do_format({insertions, deletions, overwrites, changed_resources}, :short_stat, opts)
  end

  defp do_format(changeset, :resource_only, _opts) do
    changeset
    |> changed_resources()
    |> Enum.map(&to_string/1)
    |> Enum.sort()
    |> Enum.intersperse("\n")
  end

  defp do_format(changeset, :stat, opts) do
    colorize = Keyword.get(opts, :color, Gno.ansi_enabled?())
    insertions = Changeset.Helper.inserts(changeset)
    deletions = Changeset.Helper.removals(changeset)
    overwrites = Changeset.Helper.overwrites(changeset)

    max_change_length =
      (Enum.count(insertions) + Enum.count(deletions) + Enum.count(overwrites))
      |> Integer.to_string()
      |> String.length()

    changed_resources =
      changed_resources({insertions, deletions, overwrites})
      |> Enum.map(&to_string/1)
      |> Enum.sort()

    longest_resource = changed_resources |> Enum.map(&String.length/1) |> Enum.max()
    max_resource_column_length = max_resource_column_length(max_change_length)

    {resource_column, truncate?} =
      if longest_resource > max_resource_column_length do
        {max_resource_column_length, true}
      else
        {longest_resource, false}
      end

    max_change_stats_length = terminal_width() - resource_column - max_change_length - 5

    [
      Enum.map(changed_resources, fn resource ->
        resource_insertions = insertions |> Graph.description(resource) |> Description.count()
        resource_deletions = deletions |> Graph.description(resource) |> Description.count()
        resource_overwrites = overwrites |> Graph.description(resource) |> Description.count()

        [resource_insertions_display, resource_deletions_display, resource_overwrites_display] =
          display_count(
            [resource_insertions, resource_deletions, resource_overwrites],
            max_change_stats_length
          )

        [
          " ",
          if(truncate?, do: truncate(resource, resource_column), else: resource)
          |> String.pad_trailing(resource_column),
          " | ",
          to_string(resource_insertions + resource_deletions + resource_overwrites)
          |> String.pad_leading(max_change_length),
          " ",
          ANSI.format([:green, String.duplicate("+", resource_insertions_display)], colorize),
          ANSI.format([:red, String.duplicate("-", resource_deletions_display)], colorize),
          ANSI.format([:light_red, String.duplicate("~", resource_overwrites_display)], colorize),
          "\n"
        ]
      end),
      do_format({insertions, deletions, overwrites, changed_resources}, :short_stat, opts)
    ]
  end

  defp do_format(changeset, :changes, opts) do
    colorize = Keyword.get(opts, :color, Gno.ansi_enabled?())

    changeset
    |> Changeset.Helper.merged_graph()
    |> Graph.add(Keyword.get(opts, :context_data, []))
    |> diff(diff_prefixer(changeset, colorize), colorize)
  end

  defp do_format(_, invalid, _) do
    raise ArgumentError,
          "invalid change format: #{inspect(invalid)}. Possible formats: #{Enum.join(@formats, ", ")}"
  end

  def diff(graph, line_prefixer, colorize) do
    Turtle.write_string!(graph,
      content: [
        {:separated,
         [
           :base,
           if(Graph.prefixes(graph, nil), do: :prefixes),
           :triples
         ]},
        if(colorize, do: [IO.ANSI.reset()])
      ],
      line_prefix: line_prefixer
    )
  end

  defp diff_prefixer(changeset, colorize) do
    none = if colorize, do: [IO.ANSI.reset(), "  "], else: "  "

    fn
      :triple, triple, _ ->
        if action = Changeset.Helper.action(changeset, triple) do
          change_prefix(action, colorize)
        else
          none
        end

      _, _, _ ->
        none
    end
  end

  def change_prefix(:add, false), do: "+ "
  def change_prefix(:update, false), do: "± "
  def change_prefix(:replace, false), do: "⨦ "
  def change_prefix(:remove, false), do: "- "
  def change_prefix(:overwrite, false), do: "~ "

  def change_prefix(:add, true), do: [IO.ANSI.green(), change_prefix(:add, false)]
  def change_prefix(:update, true), do: [IO.ANSI.cyan(), change_prefix(:update, false)]
  def change_prefix(:replace, true), do: [IO.ANSI.light_cyan(), change_prefix(:replace, false)]
  def change_prefix(:remove, true), do: [IO.ANSI.red(), change_prefix(:remove, false)]

  def change_prefix(:overwrite, true),
    do: [IO.ANSI.light_red(), change_prefix(:overwrite, false)]

  defp changed_resources({insertions, deletions, overwrites}) do
    insertions
    |> Graph.subjects()
    |> MapSet.new()
    |> MapSet.union(deletions |> Graph.subjects() |> MapSet.new())
    |> MapSet.union(overwrites |> Graph.subjects() |> MapSet.new())
  end

  defp changed_resources(changeset) do
    {
      Changeset.Helper.inserts(changeset),
      Changeset.Helper.removals(changeset),
      Changeset.Helper.overwrites(changeset)
    }
    |> changed_resources()
  end

  defp display_count(elements, max_change_length) do
    {elements, _remaining} =
      Enum.reduce(elements, {[], max_change_length}, fn count, {elements, remaining} ->
        if count > remaining do
          {[remaining | elements], 0}
        else
          {[count | elements], remaining - count}
        end
      end)

    Enum.reverse(elements)
  end

  defp max_resource_column_length(reserved), do: div((terminal_width() - reserved) * 95, 100)
end
