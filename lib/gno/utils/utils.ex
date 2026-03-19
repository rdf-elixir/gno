defmodule Gno.Utils do
  @moduledoc false

  def bang!(fun, args) do
    case apply(fun, args) do
      {:ok, result} -> result
      :ok -> :ok
      {:error, error} -> raise error
    end
  end

  @doc """
  Truncates a string to a maximum length and appends '...' if necessary.

  ## Examples

      iex> Gno.Utils.truncate("Hello World", 5)
      "He..."

      iex> Gno.Utils.truncate("Hello", 10)
      "Hello"
  """
  def truncate(string, max_length, trunc_suffix \\ "...") do
    if String.length(string) > max_length do
      String.slice(string, 0, max_length - String.length(trunc_suffix)) <> trunc_suffix
    else
      string
    end
  end

  def clean_ansi(iodata, false), do: iodata
  def clean_ansi(iodata, true), do: [IO.ANSI.reset() | iodata]

  @default_terminal_width_fallback 120
  def terminal_width do
    case :io.columns() do
      {:ok, columns} -> columns
      _ -> @default_terminal_width_fallback
    end
  end
end
