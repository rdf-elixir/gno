defmodule Gno.StoreCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use GnoCase, async: false

      import unquote(__MODULE__)

      setup :clean_store!
    end
  end

  def clean_store!(_) do
    :ok = Gno.drop(:all)
  end
end
