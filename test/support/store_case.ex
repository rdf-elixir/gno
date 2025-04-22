defmodule Gno.StoreCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use GnoCase, async: false

      import unquote(__MODULE__)

      setup :clean_store!
    end
  end

  alias Gno.Store
  alias Gno.Store.SPARQL.Operation

  def clean_store!(_) do
    :ok = Store.handle_sparql(Operation.drop!(), Gno.Manifest.store!(), :all)
  end
end
